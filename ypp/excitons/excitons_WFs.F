!
! License-Identifier: GPL
!
! Copyright (C) 2015 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DV
!
subroutine exciton_WFs(Xk,BS_E_degs,iq)
 !
 use pars,          ONLY:SP,cZERO,pi
 use R_lattice,     ONLY:bz_samp,qindx_X
 use units,         ONLY:BO2ANG
 use stderr,        ONLY:intc
 use D_lattice,     ONLY:a,alat
 use FFT_m,         ONLY:fft_dim
 use com,           ONLY:msg,of_open_close
 use electrons,     ONLY:spin,n_spinor
 use YPPm,          ONLY:v2plot,ncell,r_hole,l_free_hole,AVE_exc,&
&                        nr,nr_tot,output_fname,l_average_eh,&
&                        use_xcrysden,use_gnuplot,use_cube,plot_dim,&
&                        EXCITONS_user_indexes,EXCITONS_n_user_states
 use BS_solvers,    ONLY:BSS_eh_table,BS_mat,BSS_desc,BSS_n_eig
 use BS,            ONLY:BS_bands,BS_H_dim
 use interfaces,    ONLY:WF_load,WF_free,DESC_write
 use wave_func,     ONLY:WF,WF_symm,wf_ng
 use parallel_m,    ONLY:PP_indexes,myid,PP_indexes_reset
 use parallel_int,  ONLY:PP_wait,PP_redux_wait,PARALLEL_index
 use openmp,        ONLY:OPENMP_update,master_thread
 use LIVE_t,        ONLY:live_timing
 use wrapper,       ONLY:V_dot_V
 use vec_operate,   ONLY:c2a
 !
#include<y_memory.h>
 !
 type(bz_samp)     :: Xk
 integer           :: BS_E_degs(BSS_n_eig),iq
 ! 
 ! Workspace
 !
 type(PP_indexes)  :: px
 integer           :: iv,ic,ikbz,ikibz,is,neh,i1,i2,i_l,i_lambda,j_lambda,i_sp_pol,ir,ir_hole,j1,&
&                     n_lambda_deg,neh1,iv1,ic1,ikbz1,ikibz1,i_sp_pol1,is1
 integer           :: ikpbz,ikp,isp
 real(SP)          :: r_hole_rlu(3),kp_dot_r_h,k_dot_r_e
 complex(SP)       :: wf_,wf_vc(BS_H_dim),WF1_ir(n_spinor),WF2_ir(n_spinor),phase,B_coeff
 !
 integer,  allocatable :: rindex(:)
 real(SP), allocatable :: r_cell_cc(:,:)
 !
 call section('+','Excitonic Wave Function')
 !
 ! Check that directions are OK
 !
 call plot_check_and_launch(.true.)
 !
 ! Constructing Grid 
 !
 call section('+','Real-Space grid setup')
 !
 if (l_free_hole.or.l_average_eh) ncell=1
 !
 call WF_load(WF,wf_ng,1,BS_bands,(/1,Xk%nibz/),space='R',title='-EXCWF')
 !
 call expand_grid()
 !
 call k_ibz2bz(Xk,'i',.false.)
 !
 if (.not.l_free_hole.and..not.l_average_eh) then
   !
   ! Translation & location in the big grid of the hole...
   !======================================================
   ! 
   ! [1] Bare position pushed in the smallest cell 
   ! 
   call c2a(b_in=a,v_in=r_hole,v_out=r_hole_rlu,mode='kc2a')
   do j1=1,3
     r_hole_rlu(j1)=r_hole_rlu(j1)-int(r_hole_rlu(j1))
   enddo
   call c2a(b_in=a,v_in=r_hole_rlu,v_out=r_hole,mode='ka2c')
   call msg('s',' Hole position in the DL cell      ',r_hole,"[c.c.]")
   !
   ! [2] Bare position in the FFT grid
   !
   call c2a(b_in=a,v_in=r_hole,v_out=r_hole_rlu,mode='kc2a')
   r_hole_rlu(:)=nint(r_hole_rlu(:)*fft_dim(:))
   ir_hole=1+r_hole_rlu(1)+ r_hole_rlu(2)*nr(1)+ r_hole_rlu(3)*nr(1)*nr(2)
   if (ir_hole.lt.0) call error(' Hole coordinates in input must be positive') 
   call msg('s','      position in the FFT grid     ',r_cell_cc(:,ir_hole),"[c.c.]")
   !
   ! [3] Translation in the center of the Big grid
   !
   do j1=1,3
     if (ncell(j1)==1) cycle
     !
     ! (***) Daniele 15/7/07 rev Andrea 12/07:
     ! 
     ! The number of cells is always odd so that the hole can
     ! be placed in the middle.
     !
     r_hole_rlu(j1)=r_hole_rlu(j1)+ncell(j1)/2*fft_dim(j1)
     !
   enddo
   ir_hole=1+r_hole_rlu(1)+ r_hole_rlu(2)*nr(1)+ r_hole_rlu(3)*nr(1)*nr(2)
   r_hole=r_cell_cc(:,ir_hole)
   !
   call msg('s','      translated position          ',r_hole,"[c.c.]")
   call msg('s','                                   ',r_hole*BO2ANG,"[A]")
   !
 endif
 !
 ! Allocation
 !
 YAMBO_ALLOC(v2plot,(nr_tot))
 !
 ! Par Proc
 !
 call PP_indexes_reset(px)
 call PARALLEL_index(px,(/nr_tot/))
 call PP_wait()
 !
 ! Loop on exc states
 !===================
 !
 call msg('s','Processing '//trim(intc(EXCITONS_n_user_states))//' states')
 !
 do i_lambda=1,EXCITONS_n_user_states
   !
   j_lambda=EXCITONS_user_indexes(i_lambda)
   !
   n_lambda_deg=count(BS_E_degs==BS_E_degs(j_lambda))
   !
   if (n_lambda_deg>1) call msg('s',' State '//trim(intc(j_lambda))//' Merged with states '//&
&                                   trim(intc(BS_E_degs(j_lambda)))//' -> '//&
&                                   trim(intc(BS_E_degs(j_lambda)+n_lambda_deg-1)))
   !
   call live_timing('ExcWF@'//trim(intc(j_lambda)),px%n_of_elements(myid+1))  
   !
   v2plot  =0._SP
   !
   if(l_average_eh) then
     !
     do ir=1,nr_tot
       !
       if (.not.px%element_1D(ir)) cycle
       !
       do i_l=BS_E_degs(j_lambda),BS_E_degs(j_lambda)+n_lambda_deg-1
         !
         do neh = 1,BS_H_dim
           !
           ikbz  = BSS_eh_table(neh,1)
           iv    = BSS_eh_table(neh,2)
           ic    = BSS_eh_table(neh,3)
           i_sp_pol = spin(BSS_eh_table(neh,:))
           !
           ikibz = Xk%sstar(ikbz,1)
           is    = Xk%sstar(ikbz,2)
           !
           do neh1 = 1,BS_H_dim
             !
             ikbz1  = BSS_eh_table(neh1,1)
             iv1    = BSS_eh_table(neh1,2)
             ic1    = BSS_eh_table(neh1,3)
             i_sp_pol1 = spin(BSS_eh_table(neh1,:))
             !
             ikibz1 = Xk%sstar(ikbz1,1)
             is1    = Xk%sstar(ikbz1,2)
             !
             if(ikbz==ikbz1) then
               !      
               ! Build the B_{vvk} (or B_{cck} ) matrix        
               !
               if (ic1==ic.and.trim(AVE_exc)=='h') then
                 !      
                 B_coeff =  BS_mat(neh, i_l)* conjg(BS_mat(neh1, i_l))   
                 !
                 WF1_ir=WF_symm(rindex(ir),(/iv, ikibz,is,i_sp_pol/))
                 WF2_ir=WF_symm(rindex(ir),(/iv1,ikibz1,is1,i_sp_pol1/))
                 !
                 v2plot(ir) = v2plot(ir)+B_coeff*WF1_ir(1)*conjg(WF2_ir(1))
                 if(n_spinor==2) v2plot(ir) = v2plot(ir)+B_coeff*WF1_ir(2)*conjg(WF2_ir(2))
                 !
               elseif(iv1==iv.and.trim(AVE_exc)=='e') then
                 !      
                 B_coeff =  conjg(BS_mat(neh, i_l))*BS_mat(neh1, i_l)   
                 !
                 WF1_ir=WF_symm(rindex(ir),(/ic, ikibz,is,i_sp_pol/))
                 WF2_ir=WF_symm(rindex(ir),(/ic1,ikibz1,is1,i_sp_pol1/))
                 !
                 v2plot(ir) = v2plot(ir)+B_coeff*conjg(WF1_ir(1))*WF2_ir(1)
                 if(n_spinor==2) v2plot(ir) = v2plot(ir)+B_coeff*conjg(WF1_ir(2))*WF2_ir(2)
                 !
               endif
               !
             endif
             !
           enddo ! loop on neh1
           !
         enddo ! loop on neh
         !
       enddo ! loop on degenerate excitons
       !
       if (master_thread) call live_timing(steps=1)
       !
     enddo ! loop on i_r 
     !
   else
     !   
     !$omp parallel default(shared), firstprivate(ir_hole,r_hole), &
     !$omp private(wf_vc, ir,neh, ikbz,iv,ic,i_sp_pol,ikibz,is, ikpbz,ikp,isp, &
     !$omp &       k_dot_r_e,kp_dot_r_h, WF1_ir,WF2_ir,phase, i_l,wf_ )
     !
     call OPENMP_update(master_thread)
     !
     !$omp do schedule(dynamic)
     do ir=1,nr_tot
       !
       if (.not.px%element_1D(ir)) cycle
       wf_vc   =cZERO
       !
       if (l_free_hole) then
         ir_hole=ir
         r_hole=r_cell_cc(:,ir)
       endif
       !
       do neh = 1,BS_H_dim
         !
         ikbz  = BSS_eh_table(neh,1)
         iv    = BSS_eh_table(neh,2)
         ic    = BSS_eh_table(neh,3)
         i_sp_pol = spin(BSS_eh_table(neh,:))
         !
         ikibz = Xk%sstar(ikbz,1)
         is    = Xk%sstar(ikbz,2)
         !
         ikpbz = qindx_X(iq,ikbz,1)
         ikp   = Xk%sstar(ikpbz,1)
         isp   = Xk%sstar(ikpbz,2)
         !
         k_dot_r_e  = dot_product(r_cell_cc(:,ir),Xk%ptbz(ikbz,:)/alat(:))*2._SP*pi
         kp_dot_r_h = dot_product(r_hole,Xk%ptbz(ikpbz,:)/alat(:))*2._SP*pi
         !
         WF1_ir=WF_symm(rindex(ir_hole),(/iv,ikp,isp,i_sp_pol/))
         WF2_ir=WF_symm(rindex(ir     ),(/ic,ikibz,is,i_sp_pol/))
         !
         wf_vc(neh) = conjg(WF1_ir(1))*WF2_ir(1)
         if(n_spinor==2) wf_vc(neh) = wf_vc(neh) + conjg(WF1_ir(2))*WF2_ir(2)
         !
         phase=cmplx(cos(k_dot_r_e-kp_dot_r_h),sin(k_dot_r_e-kp_dot_r_h),kind=SP)
         wf_vc(neh) = wf_vc(neh)*phase
         ! 
       enddo  !Matrix elements
       !
       do i_l=BS_E_degs(j_lambda),BS_E_degs(j_lambda)+n_lambda_deg-1
         !
         wf_ = V_dot_V(BS_H_dim,BS_mat(:,i_l),wf_vc)
         !
         v2plot(ir) = v2plot(ir)+abs(wf_)**2
         !
       enddo
       !
       if (master_thread) call live_timing(steps=1)
       !
     enddo   !grid points
     !
     !$omp end do
     !$omp end parallel
     !
   endif
   !
   call live_timing()
   !
   call PP_redux_wait(v2plot)
   !
   !
   ! PLOT
   !
   if (use_cube)      output_fname='exc_qpt'//trim(intc(iq))//"_"//trim(intc(plot_dim))//'d_'//trim(intc(j_lambda))//'.cube'
   if (use_xcrysden)  output_fname='exc_qpt'//trim(intc(iq))//"_"//trim(intc(plot_dim))//'d_'//trim(intc(j_lambda))//'.xsf'
   if (use_gnuplot)   output_fname='exc_qpt'//trim(intc(iq))//"_"//trim(intc(plot_dim))//'d_'//trim(intc(j_lambda))
   !
   if (use_cube) then 
     call of_open_close(trim(output_fname),'o')
   else
    call of_open_close(trim(output_fname),'ot')
    call DESC_write('o exc','#',BSS_desc)
   endif
   !
   call plot_check_and_launch(.false.)
   !
   call of_open_close(trim(output_fname))
   !
 enddo
 !
 call PP_indexes_reset(px)
 !
 YAMBO_FREE(v2plot)
 YAMBO_FREE(r_cell_cc)
 YAMBO_FREE(rindex)
 !
 call WF_free(WF)
 !
 contains
   !
   subroutine expand_grid()
     !
     use FFT_m,       ONLY:fft_size
#include<y_memory.h>
     ! 
     ! Work Space
     !
     integer :: ir1, ir2, ir3, i3, j1, j2, j3
     logical :: warning_
     !
     warning_=.TRUE. 
     ! 
     do j1=1,3
       if (ncell(j1)<=0) ncell(j1)=1
       !
       ! Comment at (***)
       !
       if ( int(real(ncell(j1))/2.)*2== ncell(j1) ) then
         if (warning_) call warning('Forced odd number of cell replicas')
         warning_=.FALSE.
         ncell(j1)=int( real(ncell(j1))/2. )*2+1
       endif
       !
     enddo
     !
     nr_tot = fft_size*ncell(1)*ncell(2)*ncell(3)
     YAMBO_ALLOC(r_cell_cc,(3,nr_tot))
     YAMBO_ALLOC(rindex,(nr_tot))
     !
     nr=(/ncell(1)*fft_dim(1),ncell(2)*fft_dim(2),ncell(3)*fft_dim(3)/)
     call msg('s',' Extended grid ',nr)
     !
     ir = 0
     do ir1 = 0, nr(1)-1
       do ir2 = 0, nr(2)-1
         do ir3 = 0, nr(3)-1
           ir = 1 + ir1 + ir2*nr(1) + ir3*nr(1)*nr(2)
           i1=mod(ir1,fft_dim(1))
           i2=mod(ir2,fft_dim(2))
           i3=mod(ir3,fft_dim(3))
           j1=ir1/fft_dim(1)
           j2=ir2/fft_dim(2)
           j3=ir3/fft_dim(3)
           rindex(ir)=i1+fft_dim(1)*i2+fft_dim(1)*fft_dim(2)*i3+1
           r_cell_cc(:,ir) = ir1*a(1,:)/fft_dim(1) +&
&                            ir2*a(2,:)/fft_dim(2) +&
&                            ir3*a(3,:)/fft_dim(3)
         end do
       end do
     end do
     !
   end subroutine
   !
end subroutine exciton_WFs

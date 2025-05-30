!
! License-Identifier: GPL
!
! Copyright (C) 2013 The Yambo Team
!
! Authors (see AUTHORS file for details): AMDSAFFA
!
!> @callgraph
!> @callergraph
subroutine X_irredux(iq,what,X_par,Xen,Xk,Xw,X,Dip)
 !
 ! Non interacting Xo
 !
 ! OPENMP parallelism  (AF & FA)
 !   The current implementation is based on mutexes (locks).
 !   At the price of some replicated memory (Xo_res) it provides a much
 !   better omp scaling.
 !
 !   _NESTING introduces the nesting of scatterbamp parallel regions inside the
 !   outer region opened here (not working yet)
 !
 ! X terminator (BG kind) implemented (IM,AF)
 ! 
 use drivers,       ONLY:l_life
 use IO_m,          ONLY:io_RESPONSE,io_DIP
 use ALLOC,         ONLY:DIPOLE_ALLOC_global
 use pars,          ONLY:SP,cZERO,schlen
 use wrapper,       ONLY:V_plus_alpha_V,vv_caxpy
 use LIVE_t,        ONLY:live_timing
 use com,           ONLY:msg
 use matrix,        ONLY:PAR_matrix
 use stderr,        ONLY:intc
 use wave_func,     ONLY:WF
 use parallel_m,    ONLY:PAR_COM_X_WORLD,PAR_COM_RL_INDEX,myid,PAR_COM_X_WORLD_RL_resolved
 use parallel_int,  ONLY:PP_redux_wait
 use openmp,        ONLY:OPENMP_update,n_threads_X,master_thread,OPENMP_set_threads,n_threads_X,&
&                        n_out_threads,n_inn_threads,OPENMP_locks_reset,n_threads_FFT
#if defined _OPENMP
 use openmp,        ONLY:OPENMP_compute_mutex,omp_locks
#endif
 use frequency,     ONLY:w_samp,bare_grid_N,coarse_grid_N,coarse_grid_Pt
 use interfaces,    ONLY:WF_load
 use electrons,     ONLY:levels
 use R_lattice,     ONLY:qindx_X,bz_samp,G_m_G
 use D_lattice,     ONLY:i_space_inv
 use collision_el,  ONLY:elemental_collision,elemental_collision_free,elemental_collision_alloc
 use DIPOLES,       ONLY:DIPOLE_t
 use X_m,           ONLY:X_t,X_poles,X_Ein_poles,current_iq,X_poles_tab,X_lower_triangle_matrix_in_use,&
&                        self_detect_E_range,X_FILL_UP_matrix_only,use_X_DbGd,&
&                        l_X_terminator,X_terminator_E,X_term_E,X_par_lower_triangle,drude_n_states
#if defined _SC 
 use drivers,       ONLY:l_sc_run,l_eval_collisions
 use SC,            ONLY:it_now
#endif
 use gpu_m,         ONLY:have_gpu
 use devxlib,       ONLY:devxlib_memcpy_d2d,devxlib_memcpy_d2h,devxlib_memcpy_h2d
 use timing_m,      ONLY:timing
 !
#include<dev_defs.h>
#include<y_memory.h>
 !
 type(PAR_matrix), target :: X_par
 type(levels)         :: Xen
 type(bz_samp)        :: Xk
 type(X_t)            :: X
 type(DIPOLE_t)       :: Dip
 type(w_samp)         :: Xw
 integer              :: iq
 character(*)         :: what
 !
 ! Work Space
 !
 character(schlen)    :: live_t_string
 integer              :: ig1,ig_row,ig_col,ig_row_transp,ig_col_transp,iw,n_poles,i_cg,i_bg,mutexid,ngrho,&
&                        X_cols_transp(2),X_rows1,X_rows2,X_cols1,X_cols2,X_rows1_l,X_rows2_l,X_nrows_l,io_err
 logical              :: force_bare_X_G,Drude_pole,skip_WF_load
 real(SP)             :: minmax_ehe(2,PAR_COM_X_WORLD%n_CPU),cutoff
 complex(SP)          :: GreenF(Xw%n_freqs),drude_GreenF(Xw%n_freqs),ctmp(1,1)

 complex(SP),allocatable, target          :: Xo_res(:,:)
 complex(SP),allocatable, target DEV_ATTR :: Xo_res_d(:,:)
 complex(SP),allocatable DEV_ATTR :: work(:)
 complex(SP),pointer     DEV_ATTR :: Xo_res_p(:,:)
 complex(SP),pointer     DEV_ATTR :: X_par_p(:,:,:)
 complex(SP),pointer     DEV_ATTR :: X_par_lowtri_p(:,:,:)
 complex(SP)          :: GreenF_iw
 integer              :: lda,lwork,PAR_COM_RL_INDEX_n_CPU
 !
 integer, external    :: X_eh_setup
 type(elemental_collision), target :: Xo_scatt
 !
 ! Defaults & Setups
 !===================
 GreenF                           = cZERO
 drude_GreenF                     = cZERO
 !
 X_rows1=X_par%rows(1)
 X_rows2=X_par%rows(2)
 X_cols1=X_par%cols(1)
 X_cols2=X_par%cols(2)
 PAR_COM_RL_INDEX_n_CPU=PAR_COM_RL_INDEX%n_CPU
 !
 if (PAR_COM_RL_INDEX_n_CPU> 1) lda=size(X_par_lower_triangle%blc(:,1,1))
 if (PAR_COM_RL_INDEX_n_CPU==1) lda=size(X_par%blc(:,1,1))
 !
 ! Logicals to use bare or Double Grid GF (no poles accumulation)
 !=======================================================
 force_bare_X_G=use_X_DbGd.or.allocated(Xen%W).or.allocated(Xen%GreenF)
 !
 skip_WF_load= (iq==1.and.X%ng==1)
 !
 ! Drude term  !DALV: this should be move to point ### for avoiding a shift of the frequency grid in FF real-axis GW calculations 
 !============
 !if (iq==1) call X_Drude(iq,Xen,Xk,Xw,X%Wd,drude_GreenF)
 !
 ! Dipoles
 !=========
 if (iq==1) then
   call DIPOLE_dimensions(Xen,Dip,X%ib,X%q0)
   call DIPOLE_IO(Xk,Xen,Dip,'read ',io_err,'X')
 endif
 !
 ! WF load
 !=========
 ngrho=X%ng
 if (l_X_terminator) ngrho=maxval(G_m_G)
 !
 if(.not.skip_WF_load) call WF_load(WF,ngrho,maxval(qindx_X(:,:,2)),X%ib,(/1,Xk%nibz/),title='-X')
 !
 call timing(what//' (procedure)',OPR='start')
 !
 ! Poles tabulation
 !==================
 if(l_X_terminator) then
   cutoff=minval(Xen%E(X%ib(2),:,:))
   X_term_E=cutoff+X_terminator_E
 endif
 !
 if (iq/=current_iq) then
   !
   n_poles=X_eh_setup(-iq,X,Xen,Xk,minmax_ehe(:,PAR_COM_X_WORLD%CPU_id+1))
   !
   if (n_poles==0) call warning(' [CPU '//trim(intc(myid))//'] has no poles')
   !
   YAMBO_ALLOC(X_poles_tab,(n_poles,4))
   !
   if (.not.force_bare_X_G) call FREQUENCIES_coarse_grid('X',X_poles,n_poles,X%cg_percentual,X_Ein_poles,l_X_terminator)
   if (     force_bare_X_G) call FREQUENCIES_coarse_grid('X',X_poles,n_poles,0._SP,(/0.0_SP/),.FALSE.)
   !
   minmax_ehe=0._SP
   !
   n_poles=X_eh_setup(iq,X,Xen,Xk,minmax_ehe(:,PAR_COM_X_WORLD%CPU_id+1))
   !
   YAMBO_FREE(X_poles)
   YAMBO_FREE(X_Ein_poles)
   !
   if (self_detect_E_range) then
     call PP_redux_wait(minmax_ehe,COMM=PAR_COM_X_WORLD%COMM)
     Xw%er(1)=minval(minmax_ehe(1,:))
     Xw%er(2)=maxval(minmax_ehe(2,:))
   endif
   !
   ! This call is needed as Xw%p is deallocated inside
   ! the q-loop of X_em1. But only when the EM1D is written or when it is not but we are not doing
   ! lifetimes calculations
   !
   if (io_RESPONSE.or.(.not.io_RESPONSE.and..not.l_life)) call FREQUENCIES_setup(Xw)
   !
 endif
 !
 !DALV: ### the call to X_drude should be moved here, after redefining the frequency grid
 if (iq==1) call X_Drude(iq,Xen,Xk,Xw,X%Wd,drude_GreenF)
 !
#if defined _ELPH
 !
 ! Green Functions must be all mapped to the Xw range so to be easily convoluted
 !
 if (allocated(Xen%GreenF).and.current_iq==0) call X_GreenF_remap(X%ib,Xen,Xw)
 !
#endif
 !
 ! Time-Rev is Spatial Inv => only half X is eval
 !                            ===================
 if (X_FILL_UP_matrix_only.and.current_iq==0) call msg('s','[X] Upper matrix triangle filled')
 !
 ! omp settings and workspace
 !=================================
 !
 if (have_gpu) then
   n_threads_FFT=1
   n_threads_X=1
   call OPENMP_set_threads(n_threads_in=n_threads_X, use_nested=.false.)
 else
#if defined _OPENMP
#  if defined _NESTING
   call OPENMP_set_threads(n_threads_in=n_threads_X, use_nested=.true.)
   n_threads_FFT=n_inn_threads
   call msg('s','[X] NESTED openmp parallelism on: n_out_threads/n_inn_threads = ',(/n_out_threads,n_inn_threads/))
#  else
   call OPENMP_set_threads(n_threads_in=n_threads_X, use_nested=.false.)
   n_threads_FFT=1
#  endif
   if(n_threads_X>1) call OPENMP_locks_reset(INIT=.true.,nlocks=16)
#endif
 endif
 !
 ! Timing
 !========
 live_t_string=what//'@q['//trim(intc(iq))//'] '
 !
#if defined _SC 
 if (l_sc_run.and..not.l_eval_collisions) live_t_string=what//'@it['//trim(intc(it_now))//'] '
#endif
 !
 if (coarse_grid_N>=n_out_threads) call live_timing(trim(live_t_string),coarse_grid_N/n_out_threads)
 !
 X_par_p => DEV_VAR(X_par%blc)
 if (X_lower_triangle_matrix_in_use)  X_par_lowtri_p => DEV_VAR(X_par_lower_triangle%blc)

 !
 ! OpenMP setup
 !==============
 ! AF: note that DEV_OMP is switched off by the precompiler when _GPU is defined
 !
 !DEV_OMP parallel num_threads(n_out_threads) default(shared), &
 !DEV_OMP &        private(i_cg,Drude_pole,GreenF,i_bg,Xo_res,Xo_res_p,Xo_scatt,ig_col,&
 !DEV_OMP &        ig1,ig_row_transp,iw,mutexid,work,lwork,&
 !DEV_OMP &        X_rows1_l,X_rows2_l,X_nrows_l,X_cols_transp)
 !
 call OPENMP_update(master_thread)
 !
 ! memory estimate and local alloc
 !=================================
 !
 YAMBO_ALLOC(Xo_res,(X_par%rows(1):X_par%rows(2),X_par%cols(1):X_par%cols(2)))
 if (have_gpu) then
   YAMBO_ALLOC_GPU(DEV_VAR(Xo_res),(X_par%rows(1):X_par%rows(2),X_par%cols(1):X_par%cols(2)))
 endif
 !
 Xo_res_p => DEV_VAR(Xo_res)

 !
 ! workspace used in X_irredux_residuals
 ! (rhotw_save and rhotw_save2, the latter just used only with X_term)
 !
 lwork=ngrho
 if (l_X_terminator) lwork=2*ngrho
 !
 YAMBO_ALLOC_GPU(work,(lwork))
 !
 call elemental_collision_free(Xo_scatt)
 call elemental_collision_alloc(Xo_scatt,NG=ngrho,TITLE="Xo") 

 !
 ! Drude term
 !
 if (iq==1.and.master_thread.and.drude_n_states>0) then
   do i_cg = 1,coarse_grid_N
     Drude_pole= (iq==1) .and. abs(coarse_grid_Pt(i_cg))<1.E-5
     if(.not.Drude_pole) cycle
     if(.not.(X_par%rows(1)==1.and.X_par%cols(1)==1)) cycle
     !
     call X_irredux_residuals(Xen,Xk,X,Dip,i_cg,iq,Xo_res_p,Xo_scatt,work,lwork)
     !
     ! AF:
     ! ctmp is allocated as ctmp(1,1) to be compliant with devxlib interfaces
     !
     call devxlib_memcpy_d2h(ctmp,Xo_res_p,range1=[1,1],range2=[1,1])
     !
     ! DALV: we must guarantee that ctmp is always 1 and that we enter the loop just
     !       once to avoid an inconsistency with the Drude frequency given by input
     !
     X_par%blc(1,1,:)=X_par%blc(1,1,:)+ctmp(1,1)*drude_GreenF(:)
     !
     if (have_gpu) then
       do iw=1,Xw%n_freqs
         call devxlib_memcpy_h2d(DEV_VAR(X_par%blc)(1:1,1,iw),X_par%blc(1:1,1,iw))
       enddo
     endif
     !
     exit
   enddo
 endif
 !
 ! MAIN LOOP
 !===========
 !
 !DEV_OMP do
 !
 do i_cg = 1,coarse_grid_N
   !
   i_bg=sum(bare_grid_N(1:i_cg-1))+1
   !
   ! Drude term already accounted for
   !
   Drude_pole= (iq==1) .and. abs(coarse_grid_Pt(i_cg))<1.E-5
   if(Drude_pole) then
     if (master_thread) call live_timing(steps=1)
     cycle
   endif
   !
   ! 1) First compute the residuals
   !================================
   call X_irredux_residuals(Xen,Xk,X,Dip,i_cg,iq,Xo_res_p,Xo_scatt,work,lwork)
   !
   ! 2) Then the frequency dependent term
   !=======================================
   !
#if defined _ELPH
   if(     allocated(Xen%GreenF)) call X_GreenF_convoluted(iq,X_poles_tab(i_bg,:),Xw,Xen,Xk,GreenF,X%ordering)
   if(.not.allocated(Xen%GreenF)) & 
&       call X_GreenF_analytical(iq,X_poles_tab(i_bg,:),Xw,Xen,Xk,GreenF,X%ordering,'G',.FALSE.,l_X_terminator)
#else
   !
   call X_GreenF_analytical(iq,X_poles_tab(i_bg,:),Xw,Xen,Xk,GreenF,X%ordering,'G',.FALSE.,l_X_terminator)
   !
#endif
   !
   ! 3) Finally multiply residual and frequency dependent term
   !===========================================================
   !DEV_ACC_DEBUG data present(X_par_p,Xo_res_p,X_par_lowtri_p)
   freq_loop:&
   do iw=1,Xw%n_freqs
     !
     ! ----    ----
     ! -xxx    -xxx
     ! ---- => ----
     ! ----    ----
     !
#ifdef _GPU
     !
     GreenF_iw=GreenF(iw)
     !
     !DEV_ACC parallel loop collapse(2)
     !DEV_CUF kernel do(2) <<<*,*>>>
     !DEV_OMPGPU target map(present,alloc:X_par_p,Xo_res_p)
     !DEV_OMPGPU teams loop collapse(2)
     do ig_col=X_cols1,X_cols2
       do ig1=X_rows1,X_rows2
         if (ig1 <= ig_col) X_par_p(ig1,ig_col,iw)=X_par_p(ig1,ig_col,iw)+GreenF_iw*Xo_res_p(ig1,ig_col)
       enddo
     enddo
     !DEV_OMPGPU end target
     !
#else
     !
     do ig_col=X_cols1,X_cols2
       !
#  if defined _OPENMP
       if(n_threads_X>1) then
         call OPENMP_compute_mutex(ig_col,mutexid)
         call omp_set_lock(omp_locks(mutexid))
       endif
#  endif
       !
       X_rows1_l = X_rows1
       X_rows2_l = min(ig_col,X_rows2)
       X_nrows_l = X_rows2_l-X_rows1_l+1 
       !
       call V_plus_alpha_V(X_nrows_l,GreenF(iw),Xo_res(X_rows1_l:X_rows2_l,ig_col),X_par%blc(X_rows1_l:X_rows2_l,ig_col,iw))
       !
#  if defined _OPENMP
       if(n_threads_X>1) call omp_unset_lock(omp_locks(mutexid))
#  endif
     enddo
     !
#endif
     !
     if (.not.X_FILL_UP_matrix_only) then
       !
       ! ----    ----
       ! -xxx    ----
       ! ---- => -x--
       ! ----    -x--
       !
#ifdef _GPU
       !
       if (PAR_COM_RL_INDEX_n_CPU>1) then
         !
         !DEV_ACC parallel loop collapse(2) 
         !DEV_CUF kernel do(2)
         !DEV_OMPGPU target map(present,alloc:X_par_lowtri_p,Xo_res_p)
         !DEV_OMPGPU teams loop collapse(2)
         do ig_col=X_cols1,X_cols2
         do ig1=X_rows1,X_rows2
           !
           if (ig1 < ig_col) then
             ig_row_transp = ig_col
             X_par_lowtri_p(ig_row_transp,ig1,iw)=X_par_lowtri_p(ig_row_transp,ig1,iw) + &
&                                                     GreenF_iw*conjg(Xo_res_p(ig1,ig_col))
           endif
           !
         enddo
         enddo
         !DEV_OMPGPU end target
         !
       else
         !
         !DEV_ACC parallel loop collapse(2) 
         !DEV_CUF kernel do(2)
         !DEV_OMPGPU target map(present,alloc:X_par_p,Xo_res_p)
         !DEV_OMPGPU teams loop collapse(2)
         do ig_col=X_cols1,X_cols2
         do ig1=X_rows1,X_rows2
           !
           if (ig1 < ig_col) then
             ig_row_transp = ig_col
             X_par_p(ig_row_transp,ig1,iw)=X_par_p(ig_row_transp,ig1,iw)+GreenF_iw*conjg(Xo_res_p(ig1,ig_col))
           endif
           !
         enddo
         enddo
         !DEV_OMPGPU end target
         !
       endif
#else
       !
       do ig_col=X_cols1,X_cols2
         !
#  if defined _OPENMP
         if(n_threads_X>1) then
           call OPENMP_compute_mutex(ig_col,mutexid)
           call omp_set_lock(omp_locks(mutexid))
         endif
#  endif
         !
         X_rows1_l = X_rows1
         X_rows2_l = min(ig_col-1,X_rows2)
         X_nrows_l = X_rows2_l-X_rows1_l+1
         !
         ig_row_transp = ig_col
         X_cols_transp = (/X_rows1_l,X_rows2_l/)
         !
         if (PAR_COM_RL_INDEX_n_CPU>1) then
           call vv_caxpy(X_nrows_l,GreenF(iw),conjg(Xo_res(X_rows1_l:X_rows2_l,ig_col)),1, & 
&                        X_par_lower_triangle%blc(ig_row_transp,X_cols_transp(1),iw),lda)
         else
           call vv_caxpy(X_nrows_l,GreenF(iw),conjg(Xo_res(X_rows1_l:X_rows2_l,ig_col)),1, &
&                        X_par%blc(ig_row_transp,X_cols_transp(1),iw),lda)
         endif
         !
#  if defined _OPENMP
         if(n_threads_X>1) call omp_unset_lock(omp_locks(mutexid))
#  endif
         !
       enddo
#endif
       !
     endif
     !
   enddo freq_loop
   !DEV_ACC_DEBUG end data
   !
   if (master_thread) call live_timing(steps=1)
   !
 enddo 
 !
 !DEV_OMP end do
 !
 ! CLEAN
 !=======
 YAMBO_FREE_GPU(DEV_VAR(Xo_res))
 YAMBO_FREE(Xo_res)
 YAMBO_FREE_GPU(work)
 YAMBO_FREE(work)
 call elemental_collision_free(Xo_scatt)
 !
 !DEV_OMP end parallel
 !
 !
 if (iq==1.and.io_DIP) call DIPOLE_ALLOC_global()
 !
 if (coarse_grid_N>=n_out_threads) call live_timing( )
 !
 call OPENMP_update(master_thread) 
 call OPENMP_locks_reset()
 !
 current_iq=iq
 n_threads_FFT=0
 !
 call timing(what//' (procedure)',OPR='stop')
 call timing(what//' (REDUX)',OPR='start')
 !
 if (have_gpu) then
   call devxlib_memcpy_d2h(X_par%blc,DEV_VAR(X_par%blc))
   if (X_lower_triangle_matrix_in_use) call devxlib_memcpy_d2h(X_par_lower_triangle%blc,DEV_VAR(X_par_lower_triangle%blc))
   YAMBO_FREE_GPU(DEV_VAR(X_par%blc))
   YAMBO_FREE_GPU(DEV_VAR(X_par_lower_triangle%blc))
 endif
 !
 do iw=1,Xw%n_freqs
   call PP_redux_wait(X_par%blc(:,:,iw),COMM=PAR_COM_X_WORLD_RL_resolved%COMM)
   if (X_lower_triangle_matrix_in_use) call PP_redux_wait(X_par_lower_triangle%blc(:,:,iw),COMM=PAR_COM_X_WORLD_RL_resolved%COMM)
 enddo
 !
 call timing(what//' (REDUX)',OPR='stop')
 !
 ! Populate the lower triangle/piece of Xo 
 !=========================================
 !
 if (.not.X_FILL_UP_matrix_only.and.PAR_COM_RL_INDEX%n_CPU==1) return
 !
 ! X_FILL_UP_matrix_only=.TRUE.
 !
 ! oooooo
 ! xooooo
 ! xxoooo
 ! ------
 ! ------
 ! ------
 !
 ! X_FILL_UP_matrix_only=.FALSE.
 !
 ! PAR_COM_RL_INDEX%n_CPU=1
 !
 ! oooooo
 ! oooooo
 ! oooooo
 ! oooooo
 ! oooooo
 ! oooooo
 !
 ! PAR_COM_RL_INDEX%n_CPU > 1
 !
 ! oooooo    xxx---
 ! xooooo    oxx---
 ! xxoooo    oox---
 ! ------ +  ooo---
 ! ------    ooo---
 ! ------    ooo---
 !
 ! "o" = calculated
 ! "x" = to be filled now
 !
 if (X_FILL_UP_matrix_only) then
   !
   !$omp parallel do default(shared), private(iw,ig_col,ig_row,ig_row_transp,ig_col_transp), collapse(2)
   do iw=1,Xw%n_freqs
   do ig_col=X_par%cols(1),X_par%cols(2)
     ig_row_transp=ig_col
     do ig_row=max(ig_col+1,X_par%rows(1)),X_par%rows(2)
       ig_col_transp=ig_row
       if (i_space_inv==1) X_par%blc(ig_row,ig_col,iw)=      X_par%blc(ig_row_transp,ig_col_transp,iw)
       if (i_space_inv==0) X_par%blc(ig_row,ig_col,iw)=conjg(X_par%blc(ig_row_transp,ig_col_transp,iw))
     enddo
   enddo
   enddo
   !$omp end parallel do
   !
 else if (PAR_COM_RL_INDEX%n_CPU>1) then
   !
   !$omp parallel do default(shared), private(iw,ig_col,ig_row,ig_row_transp,ig_col_transp), collapse(2)
   do iw=1,Xw%n_freqs
   do ig_col=X_par%cols(1),X_par%cols(2)
     ig_row_transp=ig_col
     do ig_row=max(ig_col,X_par%rows(1)),X_par%rows(2)
       ig_col_transp=ig_row
       ! FILL THE UPPER PART OF X_par_lower
       X_par_lower_triangle%blc(ig_row_transp,ig_col_transp,iw)=X_par%blc(ig_row_transp,ig_col_transp,iw)
       ! FILL THE LOWER PART OF X_par
       X_par%blc(ig_row,ig_col,iw)                             =X_par_lower_triangle%blc(ig_row,ig_col,iw)
     enddo
   enddo
   enddo
   !$omp end parallel do
   !
 endif
 !
end subroutine

! 
! License-Identifier: GPL
!
! Copyright (C) 2019 The Yambo Team
!
! Authors (see AUTHORS file for details): CA DS AM
!
subroutine plot_interpolated_values(Xk,Xen,Ef,LOCAL_k,IDs,dims,nquantities,nfiles,basename,int_kind,i_T)
 !
 use units,          ONLY:HA2EV
 use pars,           ONLY:SP,schlen
 use com,            ONLY:msg,of_open_close
 use electrons,      ONLY:levels,n_sp_pol,n_spinor
 use vec_operate,    ONLY:iku_v_norm
 use R_lattice,      ONLY:bz_samp
 use stderr,         ONLY:intc
 use YPPm,           ONLY:coo_out,K_transform,CIRCUIT_E_db,CIRCUIT_k_label
 use interpolate,    ONLY:INTERP_obj
#if defined _YPP_SC
 use SC,             ONLY:SC_neq_kind
#endif
#if defined _YPP_RT
 use YPP_real_time,  ONLY:GreenF_T_and_W
#endif
 !
#include<y_memory.h>
 !
 type(bz_samp),    intent(in)  :: Xk,LOCAL_k
 type(levels),     intent(in)  :: Xen
 real(SP),         intent(in)  :: Ef
 integer,          intent(in)  :: IDs(nquantities),dims(2),nquantities,nfiles(nquantities),i_T
 character(*),     intent(in)  :: basename,int_kind 
 !
 ! Local variables
 !
 integer               :: ik_local,ik_ibz_grid,ik_bz_grid,iqnt,i_dim,ifile,i_point,i_sp_pol,ivalue,&
&                         ndims,nval,n_points,n_points_max
 logical               :: PLOT_BANDS,PLOT_G2,PLOT_from_DB,PLOT_interpolated,PLOT_built_in,l_print_k_name
 character(schlen)     :: headings_k(4),headings(dims(2)-dims(1)+1+4), &
&                         file_name(sum(nfiles)),k_file_name,k_name
 real(SP)              :: value_k(4),     values(dims(2)-dims(1)+1+4), &
&                         tmp_var(dims(1):dims(2),maxval(nfiles),nquantities),tmp_dist(3)
#if defined _YPP_SC
 logical               :: proj_wfc
#endif
 !
 ! Allocs
 !
 integer,  allocatable :: Grid_to_path_map(:,:)
 real(SP), allocatable :: auxiliary_var(:,:,:,:),tmp_k(:,:),tmp_k_dist(:,:)
 !
 PLOT_interpolated = index(trim(basename),"interpolated")>0
 PLOT_built_in     = index(trim(basename),"built_in")>0     
 PLOT_from_DB      = index(trim(basename),"from_DB")>0
 !
 PLOT_BANDS       = trim(int_kind)=="bands"
 PLOT_G2          = trim(int_kind)=="G_k_w"
 !
 call msg("s","Generating output for "//trim(basename)//" "//trim(int_kind))
 !
 ndims=dims(2)-dims(1)+1
 n_points=1
 n_points_max=1
 !
#if defined _YPP_SC
 proj_wfc=(trim(SC_neq_kind)=="matsubara")
#endif
 !
 if (PLOT_built_in) then
   !
   YAMBO_ALLOC(Grid_to_path_map,(LOCAL_k%nbz,Xk%nbz))
   call define_grid_map(Xk,Local_k,Grid_to_path_map,n_points_max)
   !
   if(n_points_max>1) then
     YAMBO_ALLOC(auxiliary_var,(dims(1):dims(2),maxval(nfiles),nquantities,n_points_max-1))
   endif
   !
 endif
 !
 YAMBO_ALLOC(     tmp_k,(3,n_points_max))
 YAMBO_ALLOC(tmp_k_dist,(3,n_points_max))
 !
 ! Define filenames
 !
 k_file_name= " "
 if(PLOT_G2   ) k_file_name="k-points_"//trim(basename)
 !
 file_name= " "
 !
 ifile=0
 file_name(1:nfiles(1))=trim(int_kind)//"_"//trim(basename)
 if(PLOT_BANDS) then
   do i_sp_pol=1,n_sp_pol
     ifile=ifile+1
     if (n_sp_pol>1.and.i_sp_pol==1) file_name(ifile)=trim(file_name(ifile))//"_spin-up"
     if (n_sp_pol>1.and.i_sp_pol==2) file_name(ifile)=trim(file_name(ifile))//"_spin-dn"
   enddo
 endif
 if(PLOT_G2) then
   do iqnt=1,2
     ifile=ifile+1
     if(ifile==1) file_name(ifile)=trim(file_name(ifile))//"_Re"
     if(ifile==2) file_name(ifile)=trim(file_name(ifile))//"_Im"
   enddo
 endif
 !
 if (i_T>0 ) then
   file_name(nfiles(1)+1:nfiles(1)+nfiles(2))="occupations_"//trim(basename)
   do i_sp_pol=1,n_sp_pol
     ifile=ifile+1
     if (n_sp_pol>1.and.i_sp_pol==1) file_name(ifile)=trim(file_name(ifile))//"_spin-up"
     if (n_sp_pol>1.and.i_sp_pol==2) file_name(ifile)=trim(file_name(ifile))//"_spin-dn"
   enddo
 endif
 !
 if((PLOT_interpolated.or.PLOT_built_in).and.PLOT_BANDS.and.n_spinor==2.and.i_T<2) then
   file_name(ifile+1)="spin_factors_UP_"//trim(basename)
   file_name(ifile+2)="spin_factors_DN_"//trim(basename)
   file_name(ifile+3)="magnetization_x_"//trim(basename)
   file_name(ifile+4)="magnetization_y_"//trim(basename)
   file_name(ifile+5)="magnetization_z_"//trim(basename)
   ifile=ifile+5
 endif
 !
#if defined _YPP_SC
 if(PLOT_interpolated.and.PLOT_BANDS.and.proj_wfc) then
   ifile=ifile+5
   file_name(ifile+1)="proj_val_"//trim(basename)
   file_name(ifile+2)="proj_con_"//trim(basename)
   ifile=ifile+2
 endif
#endif
 !
 if(ifile /= sum(nfiles)) call error(" something went wrong")
 !
 ! Defined headers
 !
 headings_k(1)=" |k| (a.u.) "
 headings_k(2:4)=(/"k_x ("//trim(coo_out)//")","k_y ("//trim(coo_out)//")","k_z ("//trim(coo_out)//")"/)
 !
 nval=0
 if(PLOT_BANDS) then
   headings(1)=headings_k(1)
   headings(ndims+2:ndims+4)=headings_k(2:4)
   nval=ndims+4
 endif
 if(PLOT_G2   ) then
   values(1)=0._SP
   nval=ndims+1
 endif
 !
 do i_dim=dims(1),dims(2)
   if(PLOT_BANDS) headings(1+i_dim-dims(1)+1)=' b'//intc(i_dim)
#if defined _YPP_RT
   if(PLOT_G2   ) values(1+i_dim-dims(1)+1)=real(GreenF_T_and_W%W(i_dim),SP)*HA2EV
#endif
 enddo
 !
 ! Open files and print headers
 !
 do ifile=1,sum(nfiles)
   call of_open_close(trim(file_name(ifile)),'ot')
   if(PLOT_BANDS) then
     call msg('o '//trim(file_name(ifile)),"#",headings,INDENT=0,USE_TABS=.true.)
     call msg('o '//trim(file_name(ifile)),"#")
   endif
   if(PLOT_G2) then
     call msg('o '//trim(file_name(ifile))," ",values(:nval),INDENT=0)
   endif
 enddo
 !
 ! File with KPTs
 !
 if(PLOT_G2   ) then
   !
   call of_open_close(trim(k_file_name),'ot')
   call msg('o '//trim(k_file_name),"#",headings_k,INDENT=0,USE_TABS=.true.)
   call msg('o '//trim(k_file_name),"#")
   !
 endif
 !
 ! print values
 !
 value_k =0._SP
 tmp_k_dist=0._SP
 !
 do ik_local=1,LOCAL_k%nbz
   !
   l_print_k_name=.false.
   k_name=""
   !
   if (PLOT_built_in) then
     !
     n_points=0
     do ik_bz_grid=1,Xk%nbz
       if( Grid_to_path_map(ik_local,ik_bz_grid)==-1 ) cycle
       n_points=n_points+1
       ik_ibz_grid=Xk%sstar(ik_bz_grid,1)
       !
       tmp_k_dist(:,n_points)=Xk%ptbz(ik_bz_grid,:)-LOCAL_k%pt(ik_local,:)
       tmp_k(:,n_points)=Xk%ptbz(ik_bz_grid,:)
       !
       do iqnt=1,nquantities
         if(n_points==1) tmp_var(:,1:nfiles(iqnt),iqnt)=INTERP_obj(IDs(iqnt))%SEED(dims(1):dims(2),ik_ibz_grid,:)
         if(n_points> 1) auxiliary_var(:,1:nfiles(iqnt),iqnt,n_points-1)=INTERP_obj(IDs(iqnt))%SEED(dims(1):dims(2),ik_ibz_grid,:)
       enddo
       !
     enddo
     !
   endif
   !
   if (PLOT_interpolated.or.PLOT_from_DB) then
     !
     tmp_k(:,1)=LOCAL_k%pt(ik_local,:)
     !
     if (len_trim(CIRCUIT_k_label(ik_local))>0 .and. .not.PLOT_G2) then
       k_name="  ["//trim(CIRCUIT_k_label(ik_local))//"]"
       l_print_k_name=.true.
     endif
     !
   endif
   !
   if (PLOT_interpolated) then
     !
     do iqnt=1,nquantities
       tmp_var(:,1:nfiles(iqnt),iqnt)=INTERP_obj(IDs(iqnt))%INTERP(dims(1):dims(2),ik_local,:)
     enddo
     !
     if( PLOT_BANDS) then
       if(allocated(Xen%Eo).and.allocated(CIRCUIT_E_db%E) ) then
         tmp_var(:,1:nfiles(1),1)=tmp_var(:,1:nfiles(1),1)+CIRCUIT_E_db%E(dims(1):dims(2),ik_local,:)
       endif
       tmp_var(:,1:nfiles(1),1)=tmp_var(:,1:nfiles(1),1)+Ef
     endif
     !
   endif
   !
   ! Specific for bands only
   !
   if (PLOT_from_DB.and.PLOT_BANDS) then
     !
     tmp_k(:,n_points)=LOCAL_k%pt(ik_local,:)
     tmp_var(:,1:n_sp_pol,1)=CIRCUIT_E_db%E(dims(1):dims(2),ik_local,:)+Ef
     !
   endif
   !
   if (ik_local>1) value_k(1)=value_k(1)+iku_v_norm(LOCAL_k%pt(ik_local,:)-LOCAL_k%pt(ik_local-1,:))
   !
   do i_point=1,n_points
     !
     call K_transform(tmp_k(:,i_point),'iku')
     !
     values(1)=value_k(1)+iku_v_norm(tmp_k_dist(:,i_point))
     value_k(2:4)=tmp_k(1:3,i_point)
     !
     values(ndims+2:ndims+4)=value_k(2:4)
     !
     ivalue=0
     do iqnt=1,nquantities
       do ifile=1,nfiles(iqnt)
         ivalue=ivalue+1
         if(i_point==1) values(2:ndims+1)=      tmp_var(:,ifile,iqnt)
         if(i_point> 1) values(2:ndims+1)=auxiliary_var(:,ifile,iqnt,i_point-1)
         if(PLOT_BANDS .and. ivalue<=n_sp_pol) values(2:ndims+1)=values(2:ndims+1)*HA2EV
         call msg('o '//trim(file_name(ivalue)),' ',values(:nval),INDENT=0,USE_TABS=.not.plot_G2,after_msg=k_name)
       enddo
       !
     enddo
     !
     if(PLOT_G2) call msg('o '//trim(k_file_name),' ',value_k,INDENT=0)
     !
   enddo
   !
 enddo
 !
 ! Close files
 !
 do ifile=1,sum(nfiles)
   call of_open_close(trim(file_name(ifile)))
 enddo
 if(PLOT_G2) call of_open_close(trim(k_file_name))
 !
 if(n_points_max>1) then
   YAMBO_FREE(auxiliary_var)
 endif
 !
end subroutine plot_interpolated_values
!
!
subroutine define_grid_map(Xk,Local_k,Grid_to_path_map,n_points_max)
 !
 use pars,           ONLY:SP
 use R_lattice,      ONLY:bz_samp
 use vec_operate,    ONLY:v_norm,iku_v_norm
 !
#include<y_memory.h>
 !
 type(bz_samp),  intent(in)  :: Xk,LOCAL_k
 integer,        intent(out) :: Grid_to_path_map(LOCAL_k%nbz,Xk%nbz)
 integer,        intent(out) :: n_points_max 
 !
 ! Workspace
 !
 integer               :: n_points,ik_local,ik_bz_grid
 real(SP)              :: tmp_dist(3)
 real(SP), allocatable :: circuit_versor(:,:),circuit_dist(:,:)
 !
 ! Define a map between k-points in grid and nearest k-point in circuit
 !
 YAMBO_ALLOC(circuit_versor,(3,LOCAL_k%nbz))
 YAMBO_ALLOC(circuit_dist  ,(3,LOCAL_k%nbz))
 !
 Grid_to_path_map =-1
 n_points=1
 !
 do ik_local=1,LOCAL_k%nbz-1
   tmp_dist=LOCAL_k%pt(ik_local+1,:)-LOCAL_k%pt(ik_local,:)
   circuit_dist  (:,ik_local)=tmp_dist
   circuit_versor(:,ik_local)=tmp_dist/v_norm(tmp_dist)
 enddo
 circuit_versor(:,ik_local)=circuit_versor(:,ik_local-1)
 !
 n_points_max=0
 do ik_local=1,LOCAL_k%nbz
   !
   n_points=0
   do ik_bz_grid=1,Xk%nbz
     !
     tmp_dist=Xk%ptbz(ik_bz_grid,:)-LOCAL_k%pt(ik_local,:)
     !
     if ((abs(v_norm(tmp_dist)-dot_product(tmp_dist,circuit_versor(:,ik_local)))<1.E-5_SP).and.&
     &    iku_v_norm(tmp_dist)<=iku_v_norm(circuit_dist(:,ik_local))                            ) then
       Grid_to_path_map(ik_local,ik_bz_grid)=ik_bz_grid
       n_points=n_points+1
     endif
     n_points_max=max(n_points,n_points_max)
     !
   enddo
   !
 enddo
 !
 YAMBO_FREE(circuit_versor)
 YAMBO_FREE(circuit_dist  )
 !
end subroutine define_grid_map

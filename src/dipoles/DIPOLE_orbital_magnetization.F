!
! License-Identifier: GPL
!
! Copyright (C) 2019 The Yambo Team
!
! Authors (see AUTHORS file for details): DS
!
subroutine Dipole_orbital_magnetization(Xen,Xk,Dip)
 !
 ! This routine returns <L>
 !
 use pars,                ONLY:SP,cI
 use LIVE_t,              ONLY:live_timing
 use electrons,           ONLY:levels,n_sp_pol
 use parallel_m,          ONLY:PAR_IND_DIPk_ibz,PAR_DIPk_ibz_index
 use vec_operate,         ONLY:cross_product
 use R_lattice,           ONLY:bz_samp
 use DIPOLES,             ONLY:DIP_iR,DIP_orbital,DIPOLE_t
 use parallel_m,          ONLY:PAR_IND_DIPk_ibz,PAR_DIPk_ibz_index,PAR_IND_DIPk_ibz_ID,&
&                              PAR_IND_VAL_BANDS_DIP,PAR_IND_VAL_BANDS_DIP_ID,&
&                              PAR_IND_CON_BANDS_DIP,PAR_IND_CON_BANDS_DIP_ID
 use timing_m,           ONLY:timing
 !
 implicit none
 !
 type(levels),  intent(in)    :: Xen
 type(bz_samp), intent(in)    :: Xk
 type(DIPOLE_t),intent(inout) :: Dip
 !
 ! Work Space
 !
 integer                      :: ik,ic,iv,ib,i_sp_pol,n_LT_steps,ik_mem
 real(SP)                     :: Eb,Ev,Ec
 complex(SP)                  :: DIP_pos(3,2),DIP_tmp(3)
 !
 call timing("DIPOLE_orbital_M",OPR="start")
 !
 n_LT_steps=n_sp_pol*PAR_IND_DIPk_ibz%n_of_elements(PAR_IND_DIPk_ibz_ID+1)*&
&                    PAR_IND_VAL_BANDS_DIP%n_of_elements(PAR_IND_VAL_BANDS_DIP_ID+1)*&
&                    PAR_IND_CON_BANDS_DIP%n_of_elements(PAR_IND_CON_BANDS_DIP_ID+1)
 !
 if (n_LT_steps>0) call live_timing('Orbital magnetization',n_LT_steps)
 !
 ! Main loop over k in IBZ
 !
 do i_sp_pol=1,n_sp_pol
   !
   if (n_LT_steps==0) cycle
   ! 
   do ik=1,Xk%nibz
     !
     if (.not.PAR_IND_DIPk_ibz%element_1D(ik)) cycle 
     !
     ik_mem=PAR_DIPk_ibz_index(ik)
     ! 
     do iv=Dip%ib(1),Dip%ib_lim(1) 
       !
       if(.not.PAR_IND_VAL_BANDS_DIP%element_1D(iv)) cycle
       !
       Ev=Xen%E(iv,ik,i_sp_pol)
       if (allocated(Xen%Eo)) Ev=Xen%Eo(iv,ik,i_sp_pol)
       !
       do ic=max(iv,Dip%ib_lim(2)),Dip%ib(2)
         !
         if(.not.PAR_IND_CON_BANDS_DIP%element_1D(ic)) cycle
         !
         Ec=Xen%E(ic,ik,i_sp_pol)
         if (allocated(Xen%Eo)) Ec=Xen%Eo(ic,ik,i_sp_pol)
         !
         do ib=Dip%ib(1),Dip%ib(2)
           !
           Eb=Xen%E(ib,ik,i_sp_pol)
           if (allocated(Xen%Eo)) Eb=Xen%Eo(ib,ik,i_sp_pol)
           !
           if (iv< ib) DIP_pos(:,1)=conjg(-cI*DIP_iR(:,ib,iv,ik_mem,i_sp_pol))
           if (iv>=ib) DIP_pos(:,1)=      -cI*DIP_iR(:,iv,ib,ik_mem,i_sp_pol)
           if (ic< ib) DIP_pos(:,2)=conjg(-cI*DIP_iR(:,ib,ic,ik_mem,i_sp_pol))
           if (ic>=ib) DIP_pos(:,2)=      -cI*DIP_iR(:,ic,ib,ik_mem,i_sp_pol)
           !
           DIP_tmp=-cI*cross_product(DIP_pos(:,1),DIP_pos(:,2))
           !
           ! Local part
           !
           DIP_orbital(:,ic,iv,ik_mem,i_sp_pol,1)=DIP_orbital(:,ic,iv,ik_mem,i_sp_pol,1)+Eb*DIP_tmp
           !
           ! Itinerant part
           !
           DIP_orbital(:,ic,iv,ik_mem,i_sp_pol,2)=DIP_orbital(:,ic,iv,ik_mem,i_sp_pol,2)+(Ev+Ec)/2._SP*DIP_tmp
           !
         enddo
         !
         call live_timing(steps=1)
         !
       enddo    ! conduction band loop
     enddo      ! valence    band loop
     ! 
   enddo        ! sp_pol loop
   !
 enddo          ! k-points
 !
 call live_timing()
 !
 call timing("DIPOLE_orbital_M",OPR="stop")
 !
end subroutine Dipole_orbital_magnetization

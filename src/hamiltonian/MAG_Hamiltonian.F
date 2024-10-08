!
! License-Identifier: GPL
!
! Copyright (C) 2009 The Yambo Team
!
! Authors (see AUTHORS file for details): DS AM
!
subroutine MAG_Hamiltonian()
 !
 ! WARNING: you need to put you system at the corner of the supercell <---
 !
 ! This subroutine evaluate the magnetic Hamiltonian in the space of 
 ! KS wave-functions.
 ! MAG_B and MAG_radius are given in input
 ! Landau magnetism, possible only for isolated or 1D systems
 ! If MAG_radius == 0 then Bz=MAG_B everywhere
 ! If MAG_radius /= 0 then we have the field inside a circle in each supercell.
 ! Pauli magnetism, for every system, everywhere, except when Landau is on;
 ! Then we have magnetic field in the same region of the supercell.
 !
 ! The field due to a single supercell is supposed to be:
 ! *******************************************************************************************
 !                               [  MAG_B    r<=MAG_radius
 !    Bx=0   ,   By=0    ,  Bz = {                                ====> A; B=rot(A)
 !                               [   0       r> MAG_radius  
 !
 ! With three possible gauges for the vector potential
 ! *****************************************************
 ! Gauge 0 --> Symmetric gauge
 !      [ -0.5*MAG_B y                                     [ 0.5*MAG_B x
 ! Ax = {                                             Ay = {                                          A_z=0
 !      [ -0.5*MAG_B (MAG_radius**2)*y/(x**2+y**2)         [ 0.5*MAG_B (MAG_radius**2)*x/(x**2+y**2)
 !
 ! Gauge 1 --> Asymmetric gauge (active only if MAG_radiu==0)
 ! Ax = -MAG_B y        Ay=  0              Az=0    
 ! Gauge 1 --> Asymmetric gauge (active only if MAG_radiu==0)
 ! Ax =  0              Ay=  MAG_B x        Az=0    
 ! *******************************************************************************************
 !
 use pars,           ONLY:SP,cZERO
 use units,          ONLY:SPEED_OF_LIGHT
 use hamiltonian,    ONLY:Hzero
 use FFT_m,          ONLY:fft_size
 use D_lattice,      ONLY:sigma_x,sigma_y,sigma_z
 use R_lattice,      ONLY:nkibz
 use magnetic,       ONLY:MAG_B,MAG_landau,MAG_pauli,ir_table, &
&                         A_magn_x,A_magn_y,A_magn_z,Bx,By,Bz
 use electrons,      ONLY:n_sp_pol,n_spinor,n_spin,spin
 use hamiltonian,    ONLY:H_ref_bands
 use SC,             ONLY:SC_bands
 use wave_func,      ONLY:WF,wf_x,wf_y,wf_z,WF_derivative_free
 use LIVE_t,         ONLY:live_timing
 use interfaces,     ONLY:WF_load,WF_free
 use wrapper,        ONLY:Vstar_dot_V
 use parallel_m,     ONLY:PAR_IND_QP,HEAD_QP_cpu
 use QP_m,           ONLY:QP_table,QP_n_states
 !
#include<y_memory.h>
 !
 ! Dummies
 !
 integer    :: ir,i_sp_pol,i_wf,ip_wf,ik,ib,ibp,i_qp,i_spinor,j_spinor,n_par_el
 logical    :: do_derivatives(3),H_magn_x_on,H_magn_y_on,H_magn_z_on
 logical    :: PAR_IND_local(H_ref_bands(1):H_ref_bands(2),H_ref_bands(1):H_ref_bands(2))
 !
 ! Allocs
 !
 real(SP),    allocatable :: r_cell_cc(:,:)
 complex(SP), allocatable :: H_tmp(:,:,:),H_pauli(:,:,:,:)
 real(SP),    allocatable :: H_paramagn_x(:),H_paramagn_y(:),H_paramagn_z(:),&
&                            H_diamagn(:)
 !
 call MAG_common_build_A(.true.)
 !
 H_magn_x_on=allocated(A_magn_x)
 H_magn_y_on=allocated(A_magn_y)
 H_magn_z_on=allocated(A_magn_z)
 !
 ! Symmetries check
 call Check_symmetries((/Bx,By,Bz/),"magnetic")
 !
 call local_alloc(0) 
 !
 ! Build now the magnetic Hamiltonian
 ! To calculate the m.e. of the B-induced Hamiltonian we need
 ! to evaluate the WFs derivative
 !
 ! 1) H_paramagn = 1/2*(Ax px + Ay py + Az pz) + (px Ax + py Ay + Az pz)   as [px,Ax]+[py,Ay]+[pz,Az]=0 we obtain 
 !               = (Ax px + Ay py + Az pz)            (orbital component only of H_paramagnetic)
 ! 2) H_diamagn  = 1/2*(Ax**2 + A_y**2 + A_z**2)
 ! 3) H_pauli    = 1/2*(sigma ddot rot^A)        (spin component of H_paramagnetic)
 !               = 1/2*(sigma ddot B) (remember here that the hamiltonian has a minus
 !                               which is canceled by the minus of the magnetic
 !                               moment with respect to the spin)
 if (MAG_landau) then
   ! 1) H_paramagn (the px,py,pz component will be applied directly to the wf)
   if(H_magn_x_on) H_paramagn_x(:)=A_magn_x(:)/SPEED_OF_LIGHT
   if(H_magn_y_on) H_paramagn_y(:)=A_magn_y(:)/SPEED_OF_LIGHT
   if(H_magn_z_on) H_paramagn_z(:)=A_magn_z(:)/SPEED_OF_LIGHT
   ! 2) H_diamagnetic
   if(H_magn_x_on) H_diamagn(:)=(A_magn_x(:)/SPEED_OF_LIGHT)**2
   if(H_magn_y_on) H_diamagn(:)=H_diamagn(:)+(A_magn_y(:)/SPEED_OF_LIGHT)**2
   if(H_magn_z_on) H_diamagn(:)=H_diamagn(:)+(A_magn_z(:)/SPEED_OF_LIGHT)**2
   H_diamagn(:)=0.5*H_diamagn(:)
 endif
 !
 ! 3) H_pauli
 !    Here we have MAG_B, not Bz as the Pauli matricies are chosen
 !    so that the one along the B direction is diagonal
 if(MAG_pauli) then
   if(n_sp_pol==2) then
     do ir=1,fft_size
       if(.not.ir_table(ir)) cycle
       H_pauli(ir,1,1,1)= 0.5*MAG_B/SPEED_OF_LIGHT
       H_pauli(ir,1,1,2)=-0.5*MAG_B/SPEED_OF_LIGHT
     enddo 
   else if(n_spinor==2) then
     ! Pauli matrices
     do ir=1,fft_size
       if(.not.ir_table(ir)) cycle
       H_pauli(ir,:,:,1)=Bx*sigma_x+By*sigma_y+Bz*sigma_z
     enddo 
     H_pauli=0.5*H_pauli/SPEED_OF_LIGHT
   endif
 endif
 !
 ! Local alloc/free
 !==================
 call MAG_common_build_A(.false.)
 !
 call local_free(1)
 call local_alloc(1)
 !
 if (MAG_landau) then
   do_derivatives(:)=.false.
   if(H_magn_x_on) do_derivatives(1)=.true.
   if(H_magn_y_on) do_derivatives(2)=.true.
   if(H_magn_z_on) do_derivatives(3)=.true.
 endif
 !
 PAR_IND_local=.false.
 do i_qp=1,QP_n_states
   if (.not.HEAD_QP_cpu)                 cycle
   if (.not.PAR_IND_QP%element_1D(i_qp)) cycle
   ib =QP_table(i_qp,1)
   ibp=QP_table(i_qp,2)
   PAR_IND_local(ib,ibp)=.TRUE.
 enddo 
 n_par_el=n_sp_pol*nkibz*count(PAR_IND_local)
 if(n_par_el>0) call live_timing('MAG-Hamiltonian',n_par_el)
 !
 do i_sp_pol=1,n_sp_pol   
   !
   do ik=1,nkibz   
     !
     if (MAG_landau) call WF_derivative(SC_bands,(/ik,ik/),(/i_sp_pol,i_sp_pol/),do_derivatives,.false.)
     call WF_load(WF,0,1,SC_bands,(/ik,ik/),(/i_sp_pol,i_sp_pol/),&
     &    impose_free_and_alloc=.true.,title='-MAG',keep_states_to_load=.true.)
     ! 
     PAR_IND_local=.false.
     do i_qp=1,QP_n_states
       if (.not.HEAD_QP_cpu)                 cycle
       if (     QP_table(i_qp,3) /=ik      ) cycle
       if (spin(QP_table(i_qp,:))/=i_sp_pol) cycle
       if (.not.PAR_IND_QP%element_1D(i_qp)) cycle
       ib =QP_table(i_qp,1)
       ibp=QP_table(i_qp,2)
       PAR_IND_local(ib,ibp)=.TRUE.
     enddo 
     !
     do ib=SC_bands(1),SC_bands(2)
       !
       i_wf=WF%index(ib ,ik,i_sp_pol)
       !
       do ibp=ib,SC_bands(2)
         !
         ip_wf=WF%index(ibp,ik,i_sp_pol)
         !
         if (.not.PAR_ind_local(ib,ibp) ) cycle
         !
         do j_spinor=1,n_spinor
           !
           ! Matrix Elements
           !=================
           ! Now we compute < n1| H_magn |n2 > = < n1 | H_paramagn_x | n2x> + 
           !                                     < n1 | H_paramagn_y | n2y> +
           !                                     < n1 | H_paramagn_z | n2z> +
           !                                     < n1 | H_diamagnetic| n2 >
           ! where n2x= px|n2 > ;  n2y= py|n2 > 
           !
           H_tmp=cZERO
           !
           if (MAG_landau) then
             if(H_magn_x_on) H_tmp(:,j_spinor,j_spinor)= H_paramagn_x(:)*wf_x(:,j_spinor,ip_wf)
             if(H_magn_y_on) H_tmp(:,j_spinor,j_spinor)= H_tmp(:,j_spinor,j_spinor)+H_paramagn_y(:)*wf_y(:,j_spinor,ip_wf)
             if(H_magn_z_on) H_tmp(:,j_spinor,j_spinor)= H_tmp(:,j_spinor,j_spinor)+H_paramagn_z(:)*wf_z(:,j_spinor,ip_wf)
             H_tmp(:,j_spinor,j_spinor)=H_tmp(:,j_spinor,j_spinor)+H_diamagn(:)*WF%c(:,j_spinor,ip_wf)
           endif
           !
           do i_spinor=1,n_spinor
             !
             if (MAG_pauli) H_tmp(:,i_spinor,j_spinor)= H_tmp(:,i_spinor,j_spinor) &
             &                                          +H_pauli(:,i_spinor,j_spinor,i_sp_pol)*WF%c(:,j_spinor,ip_wf)
             !
             Hzero(ib,ibp,ik,i_sp_pol)= Hzero(ib,ibp,ik,i_sp_pol)+&
&              Vstar_dot_V(fft_size,WF%c(:,i_spinor,i_wf),H_tmp(:,i_spinor,j_spinor))
             !
           enddo
           !
         enddo
         !
         if(ib/=ibp) Hzero(ibp,ib,ik,i_sp_pol)=conjg(Hzero(ib,ibp,ik,i_sp_pol))
         !
       enddo
       !
       call live_timing(steps=1)
       !
     enddo
     !
     if(MAG_landau) call WF_derivative_free()
     call WF_free(WF)
     !
   enddo
   !
 enddo
 !
 if(n_par_el>0) call live_timing()
 !
 ! Clean Up
 !
 call local_free(2)
 !
 contains
   !
   subroutine local_alloc(level)
     integer :: level
     select case(level)
       case(0)
         YAMBO_ALLOC(r_cell_cc,(fft_size,3))
         if (MAG_landau) then
           if(H_magn_x_on) then
             YAMBO_ALLOC(H_paramagn_x,(fft_size))
           endif
           if(H_magn_y_on) then
             YAMBO_ALLOC(H_paramagn_y,(fft_size))
           endif
           if(H_magn_z_on) then
             YAMBO_ALLOC(H_paramagn_z,(fft_size))
           endif
           YAMBO_ALLOC(H_diamagn,(fft_size))
           if(H_magn_x_on) H_paramagn_x=0._SP
           if(H_magn_y_on) H_paramagn_y=0._SP
           if(H_magn_z_on) H_paramagn_z=0._SP
           H_diamagn=0._SP
         endif
         if (MAG_pauli) then
           YAMBO_ALLOC(H_pauli,(fft_size,n_spin,n_spinor,n_sp_pol))
           H_pauli=cZERO
         endif
       case(1)
         YAMBO_ALLOC(H_tmp,(fft_size,n_spinor,n_spinor))
         H_tmp = cZERO
     end select
   end subroutine
   !
   subroutine local_free(level)
     integer :: level
     select case(level)
       case(1)
         YAMBO_FREE(r_cell_cc)
       case(2)
         if (MAG_landau) then
           if(H_magn_x_on) then
             YAMBO_FREE(H_paramagn_x)
           endif
           if(H_magn_y_on) then
             YAMBO_FREE(H_paramagn_y)
           endif
           if(H_magn_z_on) then
             YAMBO_FREE(H_paramagn_z)
           endif
           YAMBO_FREE(H_diamagn)
         endif
         if (MAG_pauli)  then
           YAMBO_FREE(H_pauli)
         endif
         YAMBO_FREE(H_tmp)
     end select
  end subroutine
  !
end subroutine

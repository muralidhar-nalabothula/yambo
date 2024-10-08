!
! License-Identifier: GPL
!
! Copyright (C) 2007 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
integer function X_eh_setup(iq,X,Xen,Xk,minmax_ehe)
 !
 use pars,          ONLY:SP
 use X_m,           ONLY:X_t,X_poles,X_Ein_poles,X_poles_tab,l_X_terminator,X_term_E
 use R_lattice,     ONLY:qindx_X,bz_samp
 use electrons,     ONLY:levels,n_sp_pol,spin_occ
 use frequency,     ONLY:ordered_grid_index
 use parallel_m,    ONLY:PAR_IND_CON_BANDS_X,PAR_IND_Xk_bz,PAR_IND_VAL_BANDS_X
 !
#include<y_memory.h>
 !
 type(levels)  ::Xen 
 type(bz_samp) ::Xk
 type(X_t)     ::X
 integer       ::iq
 real(SP)      ::minmax_ehe(2)
 !
 ! Work Space
 !
 integer :: ik_bz,i_sym,ik,ik_m_q,iv,ic,Nv(n_sp_pol),Nc(n_sp_pol),i_sp,i_pole,ic_min,Nc_XTerm(n_sp_pol),N_tot
 logical :: MPI_logicals_on,l_XTerm_vv
 real(SP):: E_eh,E_in,f_eh,local_tresh
 real(SP), allocatable :: poles(:),Ein_poles(:)
 !
 do i_sp=1,n_sp_pol
   Nv(i_sp)=Xen%nbm(i_sp)-X%ib(1)+1
   Nc(i_sp)=X%ib(2)-Xen%nbf(i_sp)
 enddo
 !
 Nc_XTerm=0
 if (l_X_terminator) Nc_XTerm=Nv
 !
 N_tot=0
 do i_sp=1,n_sp_pol
   N_tot=N_tot+Nv(i_sp)*(Nc(i_sp)+Nc_XTerm(i_sp))
 enddo
 !
 YAMBO_ALLOC(poles,(Xk%nbz*N_tot))
 YAMBO_ALLOC(Ein_poles,(Xk%nbz*N_tot))
 !
 MPI_logicals_on=allocated(PAR_IND_Xk_bz%element_1D)
 !
 ! Note that in metals not all the elements are defined
 !
 poles=0._SP 
 Ein_poles=0._SP
 !
 !
 X_eh_setup=0
 local_tresh=epsilon(1._SP)
 !
 do i_sp=1,n_sp_pol
 do ik_bz=1,Xk%nbz
   !
   if (MPI_logicals_on) then
     if (.not.PAR_IND_Xk_bz%element_1D(ik_bz)) cycle 
   endif
   !
   do iv=X%ib(1),X%ib(1)+Nv(i_sp)-1
     !
     if (MPI_logicals_on) then
       if (.not.PAR_IND_VAL_BANDS_X(X%whoami)%element_1D(iv)) cycle 
     endif
     !
     ! setting terminator bnd range
     ic_min = X%ib(2)-Nc(i_sp)+1
     if (l_X_terminator) ic_min=X%ib(1) 
     !
     do  ic=ic_min,X%ib(2)
         !
         if (MPI_logicals_on) then
           if (.not.PAR_IND_CON_BANDS_X(X%whoami)%element_1D(ic)) cycle 
         endif
         !
         i_sym  =qindx_X(iabs(iq),ik_bz,1)
         ik     =Xk%sstar(ik_bz,1) 
         ik_m_q =Xk%sstar(i_sym,1)
         !
         ! terminator handling
         if (ic>=X%ib(1).and.ic<=Xen%nbm(i_sp).and.l_X_terminator) then
           l_XTerm_vv=.TRUE.
           E_eh=X_term_E-Xen%E(iv,ik_m_q,i_sp)       
         else
           l_XTerm_vv=.FALSE.
           E_eh=Xen%E(ic,ik,i_sp)-Xen%E(iv,ik_m_q,i_sp)
         endif 
         !
         E_in=Xen%E(iv,ik_m_q,i_sp)
         !
         ! Note that all possible E_eh signs are accepted. Negative
         ! transitions energies appear at finite temperature.
         !
         ! The way to distinguish between resonant and anti-reonant transitions
         ! is to check fv(1-fc) factor that comes from the t>0 ordering
         ! of the G's function. In this way, however, E_eh can be negative as
         ! shown below
         !
         ! n(E) ----     
         !          *    
         !          4*  3
         !            -.   
         !              *
         !          1   2-._______
         !          -Eeh-
         !
         !   1,2 = v , 3,4 = c
         !
         !   both transitions 1->3 , 2->4 are resonant but 2->4 has negative energy
         !
         ! When iv--> iv transitions are counted, f_eh=0. 
         ! Therefore  if (abs(f_eh)<local_tresh) cycle hold only 
         ! when the terminator  is off 
         !
         if (.not.l_XTerm_vv) f_eh=Xen%f(iv,ik_m_q,i_sp)*(spin_occ-Xen%f(ic,ik,i_sp))/spin_occ
         if (     l_XTerm_vv) f_eh=Xen%f(iv,ik_m_q,i_sp)*Xen%f(ic,ik,i_sp)/spin_occ
         !
         if (abs(f_eh)<local_tresh)  cycle  
         !                                                              
         if (any((/abs(E_eh)<X%ehe(1),abs(E_eh)>X%ehe(2).and.X%ehe(2)>0._SP/))) cycle
         !
         X_eh_setup=X_eh_setup+1
         poles(X_eh_setup)=E_eh
         Ein_poles(X_eh_setup)=E_in
         !
         i_pole=X_eh_setup
         if (allocated(ordered_grid_index)) i_pole=ordered_grid_index(X_eh_setup)
         if (iq>0) X_poles_tab(i_pole,:)=(/ik_bz,iv,ic,i_sp/)
         !
       enddo
     enddo
   enddo
 enddo
 !
 minmax_ehe=(/max(minval(poles(:X_eh_setup))-0.1_SP,0._SP),maxval(poles(:X_eh_setup))+0.1_SP/)
 !
 if (iq<0) then
   if (.not.allocated(X_poles)) then
     YAMBO_ALLOC(X_poles,(X_eh_setup))
     X_poles=0._SP
   endif
   X_poles=X_poles+poles(:X_eh_setup)
   !
   if (.not.allocated(X_Ein_poles)) then
     YAMBO_ALLOC(X_Ein_poles,(X_eh_setup))
     X_Ein_poles=0._SP
   endif
   X_Ein_poles=X_Ein_poles+Ein_poles(:X_eh_setup)
 endif
 !
 YAMBO_FREE(poles)
 YAMBO_FREE(Ein_poles)
 !
end function

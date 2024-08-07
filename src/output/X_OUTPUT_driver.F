!
! License-Identifier: GPL
!
! Copyright (C) 2021 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine X_OUTPUT_driver(WHAT,keys,solver,IQ,IG,DESC,data,indexes)
 !
 use pars,          ONLY:schlen,SP
 use D_lattice,     ONLY:l_0D,l_1D,l_2D
 use X_m,           ONLY:X_obs,N_X_obs,alpha_dim,X_obs_onoff,X_do_obs
 use drivers,       ONLY:l_chi,l_optics,l_bs_fxc
 use electrons,     ONLY:n_spinor
 use PHOTOLUM,      ONLY:PL
 use BS,            ONLY:l_BS_kerr,l_BS_magnons,l_BS_dichroism,BS_K_coupling,&
&                        l_BS_photolum,l_BS_abs,l_BS_jdos,l_BS_esort_indx,l_BS_esort
 use BS_solvers,    ONLY:l_abs_prop_chi_bse,l_eels_can_be_computed
 use stderr,         ONLY:STRING_match,STRING_split,intc,STRING_remove
 use OUTPUT,         ONLY:OUTPUT_driver
 use interfaces,     ONLY:DESC_write
 use descriptors,    ONLY:IO_desc
 use parser_m,       ONLY:parser
 !
 implicit none
 !
 character(*)           :: WHAT
 character(*), optional :: keys
 character(*), optional :: solver
 integer,      optional :: IQ,IG
 type(IO_desc),optional :: DESC
 real(SP),     optional :: data(:)
 integer,      optional :: indexes(:)
 !
 ! Work Space
 integer            ::it,itp,ik,ic
 character(schlen)  ::key(10),BASIC_col(7)
 character(5)       ::obs_with_res(7)
 logical            ::l_flag,l_print_res
 !
 if (STRING_match(WHAT,"DEF")) then
   call ELEMENTAL_init(1,"fxc","Exchange-Correlation Kernel","optics")
   call ELEMENTAL_init(2,"E_INDX_IP","Sorted IP Energies indexes","indexes")
   call ELEMENTAL_init(3,"E_IP","Sorted IP Energies","sort")
   call ELEMENTAL_init(4,"Esort","Sorted Interacting Energies","sort")
   call ELEMENTAL_init(5,"pl","Photoluminescence","PL")
   call ELEMENTAL_init(6,"eps","Absorption","optics")
   call ELEMENTAL_init(7,"refl","Reflectivity","optics")
   call ELEMENTAL_init(8,"eel","Electron Energy Loss","optics")
   call ELEMENTAL_init(9,"alpha","Polarizability  ( -<<X>> )","optics")
   call ELEMENTAL_init(10,"off","Off-diagonal Absorption","kerr")
   call ELEMENTAL_init(11,"beta","Off-diagonal Polarizability","kerr")
   call ELEMENTAL_init(12,"moke","MOKE parameters","kerr")
   call ELEMENTAL_init(13,"jdos","Joint Density of states","optics")
   call ELEMENTAL_init(14,"CD","Dichroism","dichroism")
   call ELEMENTAL_init(15,"Spm","Magnons (S+-)","magnons")
   call ELEMENTAL_init(16,"Smp","Magnons (S-p)","magnons")
 endif
 !
 if (STRING_match(WHAT,"INIT")) then
   !
   ! Logicals activation...
   !------------------------
   if (l_bs_fxc) call X_obs_onoff("+ fxc")
   if (l_BS_photolum) call X_obs_onoff("+ pl")
   if (l_BS_abs.or.l_BS_kerr.or.(l_optics.and.l_chi)) then
     call X_obs_onoff("+ eps")
     call X_obs_onoff("+ eel")
     if (trim(alpha_dim)/='adim') call X_obs_onoff("+ alpha")
   endif
   !
   ! Switch off macroscopic quantities for lower dim materials
   if (l_0D.or.l_1D.or.l_2D) call X_obs_onoff("- eel eps off")
   ! Switch off eels if it cannot be computed
   if (.not.l_eels_can_be_computed) call X_obs_onoff("- eel")
   !
   if (l_BS_abs) then
     call parser('Reflectivity',l_flag)
     if (l_flag) call X_obs_onoff("+ refl") 
   endif
   if (l_BS_jdos) call X_obs_onoff("+ jdos")
   if (l_BS_esort)      call X_obs_onoff("+ Esort E_IP")
   if (l_BS_esort_indx) call X_obs_onoff("+ E_INDX_IP")
   if (l_BS_kerr) then
     if (X_do_obs("alpha")) call X_obs_onoff("+ beta")
     if (X_do_obs("eps"))   call X_obs_onoff("+ off moke")
   endif
   if (l_BS_magnons) call X_obs_onoff("+ Spm")
   if (l_BS_magnons.and.n_spinor==2) call X_obs_onoff("+ Smp")
   if (l_BS_dichroism) call X_obs_onoff("+ CD")
   !
   !...solvers specific
   if (present(solver)) then
     if (STRING_match(solver,"Slepc")) then
       if( l_abs_prop_chi_bse      .and. X_do_obs("eel") ) then
         call X_obs_onoff("- eel")
	 call warning("eels evaluation switched off for slepc")
       endif
       if((.not.l_abs_prop_chi_bse).and.(X_do_obs("eps").or.X_do_obs("alpha"))) then
         call X_obs_onoff("- eps alpha")
	 call warning("eps & alpha evaluation switched off for slepc")
       endif
     endif
     if (STRING_match(solver,"Inversion")) call X_obs_onoff("- Esort E_IP E_INDX_IP kerr magnons jdos")
     if (STRING_match(solver,"Haydock")) call X_obs_onoff("- Esort jdos E_IP E_INDX_IP")
     if (STRING_match(solver,"Diago").or.STRING_match(solver,"Slepc")) call X_obs_onoff("- E_IP E_INDX_IP")
   endif
   !
   ! Headers...
   !------------
   ! ... specific
   if (X_do_obs("fxc")) then
     X_obs(1)%N_columns=2
     X_obs(1)%COL_header(1)   = 'E'
     X_obs(1)%COL_header(2:3) = (/'Re(q^2Fxc)','Re(q^2Fxc)'/)
   endif
   if (X_do_obs("indexes")) then
     X_obs(2)%N_columns=6
     X_obs(2)%COL_header(1:6)  = (/' E  ','ikbz','ib1 ','ib2 ','isp1','isp2'/)
   endif
   if (X_do_obs("Esort")) then
     do ic=3,4
       X_obs(ic)%N_columns=2
       X_obs(ic)%COL_header(1:2)  = (/'E    ','N_deg'/)
     enddo
     if (BS_K_coupling) then
       X_obs(4)%N_columns=3
       X_obs(4)%COL_header(1:3)  = (/'Re(E)','Im(E)','N_deg'/)
     endif
     obs_with_res=[character(5) :: "eps","alpha","Spm","Smp","off","beta","CD" ]
     do it=1,N_X_obs
       if (.not.X_do_obs(trim(X_obs(it)%what))) cycle
       l_print_res=.false.
       do itp=1,7
         l_print_res=l_print_res.or.trim(X_obs(it)%what)==trim(obs_with_res(itp))
       enddo
       if (.not.l_print_res) cycle
       do ic=3,4
         X_obs(ic)%N_columns=X_obs(ic)%N_columns+1
         X_obs(ic)%COL_header(X_obs(ic)%N_columns) =trim(X_obs(it)%what) 
       enddo
     enddo
   endif
   if (X_do_obs("PL")) then
     X_obs(5)%N_columns=3
     X_obs(5)%COL_header(1)   = 'E'
     X_obs(5)%COL_header(2:3) = (/'PL  ','PL_o'/)
   endif
   !
   ! ... pre-formatted
   BASIC_col(1)   = 'E[1]'
   BASIC_col(2:3) = (/'Im(XXX)', 'Re(XXX)'/)
   BASIC_col(4:5) = (/'Im(XXX_o)', 'Re(XXX_o)'/)
   BASIC_col(6:7) = (/'Im(XXX`)','Re(XXX`)'/)
   do it=6,N_X_obs
     X_obs(it)%N_columns=7 
     do ic=1,X_obs(it)%N_columns
       X_obs(it)%COL_header(ic)=STRING_remove(BASIC_col(ic),"XXX",trim(X_obs(it)%what))
     enddo
   enddo
   !
 endif
 !
 if (STRING_match(WHAT,"keys")) then
   key=' '
   if (present(keys)) call STRING_split(keys,key)
   do it=1,N_X_obs
     if (.not.IS_this_ok(it)) cycle
     if (present(IQ)) then
       X_obs(it)%prefix=trim(X_obs(it)%prefix)//"_q"//trim(intc(IQ))
     endif
     if (present(IG)) then
       if (IG>1) X_obs(it)%prefix=trim(X_obs(it)%prefix)//"_G"//trim(intc(IG))
     endif
     do ik=1,10 
       if (len_trim(key(ik))==0) cycle
       X_obs(it)%prefix=trim(X_obs(it)%prefix)//"_"//trim(key(ik))
     enddo
   enddo
   return
 endif
 !
 if (STRING_match(WHAT,"open").or.STRING_match(WHAT,"append").or.STRING_match(WHAT,"override")) then
   do it=1,N_X_obs
     if (.not.IS_this_ok(it)) cycle
     if (STRING_match(WHAT,"open")) call OUTPUT_driver(trim(X_obs(it)%prefix),action="open")  
     if (STRING_match(WHAT,"override")) call OUTPUT_driver(trim(X_obs(it)%prefix),action="override")  
     if (STRING_match(WHAT,"append")) call OUTPUT_driver(trim(X_obs(it)%prefix),action="append")  
   enddo
 endif
 !
 if ((STRING_match(WHAT,"DESC").and.present(DESC)).or.STRING_match(WHAT,"close").or.STRING_match(WHAT,"reset")) then
   do it=1,N_X_obs
     if (.not.IS_this_ok(it)) cycle
     if (STRING_match(WHAT,"DESC" )) call DESC_write("o "//trim(X_obs(it)%prefix),'#',DESC)
     if (STRING_match(WHAT,"close")) call OUTPUT_driver(trim(X_obs(it)%prefix),action="close")
     if (STRING_match(WHAT,"reset")) call OUTPUT_driver(trim(X_obs(it)%prefix),action="reset")
   enddo
 endif
 !
 if (STRING_match(WHAT,"WRITE")) then
   do it=1,N_X_obs
     if (.not.IS_this_ok(it)) cycle
     call OUTPUT_driver(trim(X_obs(it)%prefix),R_VALUES=data(1:1),TITLES=X_obs(it)%COL_header(1:1),UNIT="eV")
     do ic=2,size(data)
       call OUTPUT_driver(trim(X_obs(it)%prefix),R_VALUES=data(ic:ic),TITLES=X_obs(it)%COL_header(ic:ic))
     enddo
     if (present(indexes)) then
       do ic=1,size(indexes)
         call OUTPUT_driver(trim(X_obs(it)%prefix),I_VALUES=indexes(ic:ic),TITLES=X_obs(it)%COL_header(ic+1:ic+1))
       enddo
     endif
     call OUTPUT_driver(trim(X_obs(it)%prefix),action="write")
   enddo
 endif
 !
 contains
   !
   logical function IS_this_ok(it)
     integer  :: it
     IS_this_ok=X_obs(it)%active
     if (.not.IS_this_ok) return
     if (.not.STRING_match(WHAT,trim(X_obs(it)%what) )) IS_this_ok=.FALSE.
     if (STRING_match(WHAT,trim(X_obs(it)%scattering))) IS_this_ok=.TRUE.
     if (STRING_match(WHAT,"ALL")) IS_this_ok=.TRUE.
   end function
   !
   subroutine ELEMENTAL_init(it,short,long,scattering)
     integer      :: it
     character(*) :: short,long,scattering
     X_obs(it)%what=short
     X_obs(it)%title=long
     X_obs(it)%scattering=scattering
     X_obs(it)%N_messages=0
     X_obs(it)%N_columns=0
     X_obs(it)%active=.FALSE.
     X_obs(it)%prefix=X_obs(it)%what
   end subroutine
 !
end subroutine

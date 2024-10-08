!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): CA
!
real(SP) function Eliashberg_Dos_Func(iq,im,ph_en, ph_broad, PH_E, q) 
 !
 use pars,                ONLY:SP
 use electrons,           ONLY:levels
 use R_lattice,           ONLY:bz_samp
 use functions,           ONLY:Fermi_fnc_derivative
 use ELPH,                ONLY:PH_freqs_sq,use_PH_DbGd
 !
#include<y_memory.h>
 !
 integer,      intent(in) :: iq,im
 real(SP),     intent(in) :: ph_en,ph_broad
 type(levels), intent(in) :: PH_E
 type(bz_samp),intent(in) :: q
 !
 ! work space
 !
 real(SP) :: omega,weight
 integer  :: iq_fg,iE_fg,iqbz
 !     
 omega = sqrt( MAX( PH_freqs_sq(iq,im),0. ) )
 !
 Eliashberg_Dos_Func=Fermi_fnc_derivative(ph_en-omega,ph_broad)
 !
 if(.not.use_PH_DbGd) return
 !
 iqbz=q%k_table(iq,1)
 !
 weight=1.0/(q%FGbz%k_range(iqbz,2)-q%FGbz%k_range(iqbz,1)+1._SP)
 !
 do iq_fg=q%FGbz%k_range(iqbz,1)+1,q%FGbz%k_range(iqbz,2),1
   iE_fg =q%FGbz%E_map(iq_fg)
   omega=PH_E%FG%E(im,iE_fg,1)
   Eliashberg_Dos_Func=Eliashberg_Dos_Func+Fermi_fnc_derivative(ph_en-omega,ph_broad)
 enddo
 !
 Eliashberg_Dos_Func=Eliashberg_Dos_Func*weight
 !
end function

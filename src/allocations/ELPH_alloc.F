!
! License-Identifier: GPL
!
! Copyright (C) 2020 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine ELPH_alloc(what,GKKP,Nb,Nm,Nk_mem,Nq_mem)
 !
 use pars,          ONLY:rZERO,cZERO,schlen
 use D_lattice,     ONLY:n_atoms
 use R_lattice,     ONLY:nkbz,nqbz
 use electrons,     ONLY:E_reset
 use QP_m,          ONLY:QP_n_states
 use ELPH,          ONLY:GKKP_me,PH_pol_vector,ph_modes,PH_freqs_sq,&
&                        PH_acoustic_speed,PH_acoustic_branch,gsqF_life_f,gsqF_life_bose,gsqF_fan,&
&                        gsqF_ca_corr,gsqF_dw,PH_Q_modulus,PH_qpt,elph_nb,elph_nQ,eval_G_using_KK,&
&                        gsqF_energy_steps,PH_kpt_bz,elph_nk_bz,elph_use_q_grid,FineGd_E_kpq_components_reset
 use parallel_m,    ONLY:PAR_nQ_bz
 use stderr,        ONLY:STRING_split
 !
#include<y_memory.h>
 !
 character(*)            ::what
 type(GKKP_me), optional ::GKKP
 integer,       optional ::Nb(2),Nk_mem,Nm(2),Nq_mem
 !
 ! Work Space
 !
 integer          ::iq,is,NS,nq_BZ
 character(schlen)::strings(10)
 !
 call STRING_split(what,strings,n_non_empty_strings=NS)
 !
 if (present(GKKP)) then
   GKKP%Nq_mem=1
   GKKP%Nb=(/1,elph_nb/)
   GKKP%Nmodes=(/1,ph_modes/)
   GKKP%Nk_mem=nkbz
   if (present(Nq_mem)) then
     GKKP%Nq_mem=Nq_mem
   endif
   if (present(Nb)) then
     GKKP%Nb=Nb
   endif
   if (present(Nm)) then
     GKKP%Nmodes=Nm
   endif
   if (present(Nk_mem)) then
     GKKP%Nk_mem=Nk_mem
   endif
 endif
 !
 do is=1,NS
   !
   select case (trim(strings(is)))
     !
     case ('DW','dV_sq')
       if (.not.allocated(GKKP%dVr)) then
         GKKP%KIND=trim(strings(is))
         YAMBO_ALLOC(GKKP%dVr,(GKKP%Nmodes(1):GKKP%Nmodes(2),GKKP%Nb(1):GKKP%Nb(2),GKKP%Nb(1):GKKP%Nb(2),GKKP%Nk_mem,GKKP%Nq_mem))
         GKKP%dVr=rZERO
       endif
       !
     case ('dV','dV_bare')
       if (.not.allocated(GKKP%dVc)) then
         GKKP%KIND=trim(strings(is))
         YAMBO_ALLOC(GKKP%dVc,(GKKP%Nmodes(1):GKKP%Nmodes(2),GKKP%Nb(1):GKKP%Nb(2),GKKP%Nb(1):GKKP%Nb(2),GKKP%Nk_mem,GKKP%Nq_mem))
         GKKP%dVc=cZERO
       endif
       !
     case ('LEVELS')
       if (.not.allocated(GKKP%E_kpq)) then
         allocate(GKKP%E_kpq(elph_nQ))
         do iq=1,elph_nQ
           YAMBO_ALLOC(GKKP%E_kpq(iq)%E,(elph_nb,nkbz,1))
           YAMBO_ALLOC(GKKP%E_kpq(iq)%f,(elph_nb,nkbz,1))
         enddo
       endif
     case ('DGRID')
       if (.not.allocated(GKKP%E_dg_kpq)) then
         if (elph_use_q_grid) then
            nq_BZ=nqbz
         else
            nq_BZ=elph_nQ
         endif
         allocate(GKKP%E_dg_kpq(nq_BZ))
       endif
     case ('gFsq')
       !
       if (.not.allocated(gsqF_fan)) then
         if (.not.eval_G_using_KK) then
           YAMBO_ALLOC(gsqF_fan,(QP_n_states,PAR_nQ_bz,ph_modes,gsqF_energy_steps))
           YAMBO_ALLOC(gsqF_ca_corr,(QP_n_states,PAR_nQ_bz,ph_modes,gsqF_energy_steps))
           gsqF_fan=rZERO
           gsqF_ca_corr=rZERO
         endif
         YAMBO_ALLOC(gsqF_dw,(QP_n_states,PAR_nQ_bz,ph_modes))
         YAMBO_ALLOC(gsqF_life_bose,(QP_n_states,PAR_nQ_bz,ph_modes,gsqF_energy_steps))
         YAMBO_ALLOC(gsqF_life_f,(QP_n_states,PAR_nQ_bz,ph_modes,gsqF_energy_steps))
         gsqF_dw=rZERO
         gsqF_life_bose=rZERO
         gsqF_life_f=rZERO
       endif
       !
     case ('PHONONS')
       !
       if (.not.allocated(PH_freqs_sq)) then
         !
         YAMBO_ALLOC(PH_freqs_sq,(elph_nQ,ph_modes))
         YAMBO_ALLOC(PH_pol_vector,(ph_modes,n_atoms,3,elph_nQ))
         YAMBO_ALLOC(PH_qpt,(elph_nQ,3))
         YAMBO_ALLOC(PH_kpt_bz,(elph_nk_bz,3))
         YAMBO_ALLOC(PH_Q_modulus,(elph_nQ))
         YAMBO_ALLOC(PH_acoustic_speed,(elph_nQ,ph_modes))
         YAMBO_ALLOC(PH_acoustic_branch,(ph_modes))
         PH_pol_vector=rZERO
         PH_qpt=rZERO
         PH_kpt_bz=rZERO
         PH_freqs_sq=rZERO
         PH_Q_modulus=rZERO
         PH_acoustic_speed=rZERO
         PH_acoustic_branch=.FALSE.
         !
       endif
       !
     case ('FREE')
       if (.not.present(GKKP)) then
         !
         YAMBO_FREE(gsqF_fan)
         YAMBO_FREE(gsqF_dw)
         YAMBO_FREE(gsqF_ca_corr)
         YAMBO_FREE(gsqF_life_bose)
         YAMBO_FREE(gsqF_life_f)
         !
         YAMBO_FREE(PH_Q_modulus)
         YAMBO_FREE(PH_acoustic_speed)
         YAMBO_FREE(PH_acoustic_branch)
         !
         YAMBO_FREE(PH_freqs_sq)
         YAMBO_FREE(PH_pol_vector)
         YAMBO_FREE(PH_qpt)
         YAMBO_FREE(PH_kpt_bz)
         !
         YAMBO_FREE(gsqF_fan)
         YAMBO_FREE(gsqF_ca_corr)
         YAMBO_FREE(gsqF_dw)
         YAMBO_FREE(gsqF_life_bose)
         YAMBO_FREE(gsqF_life_f)
         !
       else
         YAMBO_FREE(GKKP%dVr)
         YAMBO_FREE(GKKP%dVc)
         if (allocated(GKKP%E_kpq)) then
           do iq=1,elph_nQ
             call E_reset( GKKP%E_kpq(iq) )
           enddo
           deallocate(GKKP%E_kpq)
         endif
         if (allocated(GKKP%E_dg_kpq)) then
           nq_BZ=size(GKKP%E_dg_kpq)
           do iq=1,nq_BZ
             call FineGd_E_kpq_components_reset( GKKP%E_dg_kpq(iq) )
           enddo
           deallocate(GKKP%E_dg_kpq)
         endif
       endif
       !
   end select
   !
 enddo
 !
end subroutine

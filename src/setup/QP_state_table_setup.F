!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine QP_state_table_setup(en)
 !
 ! There are 2 objects that command the QP corrections
 ! indexes: QP_state & QP_table.
 !
 ! QP_table gives the band/k indexes for any QP state
 ! QP_state is T if that band/k is a QP state
 !
 ! QP_state is read from QP based DBs
 !
 ! IN :  either input_file or QP_state
 ! Out:  QP_table(1:QP_n_states,:) = (n,n`,ikibz)
 !       QP_state
 !
 use pars,          ONLY:SP
 use units,         ONLY:HA2EV
 use drivers,       ONLY:l_sc_run,l_real_time,l_eval_collisions,l_nl_optics
 use QP_m,          ONLY:QP_nk,QP_nb,QP_state,QP_n_states,QP_table,SC_bands_mixed,SC_band_mixing 
 use electrons,     ONLY:levels,n_sp_pol
 use parser_m,      ONLY:PARSER_array
#if defined _SC || defined _RT
 use hamiltonian,   ONLY:H_ref_bands,H_potential
 use drivers,       ONLY:l_elel_scatt
#endif
#if defined _SC
 use SC,            ONLY:l_SC_diagonal
#endif
 !
#include<y_memory.h>
 type(levels)::en
 !
 ! Work Space
 !
 integer :: e_rng_lines,k_rng_lines,ik,ib,i1,i2,i3,&
&           QP_k_nk,QP_e_nk,QP_k_nb,QP_e_nb,i_sp,bands_mixed,v(2)
 logical :: Mixing
 integer,    allocatable:: QP_i_limits(:,:)
 real(SP)   ,allocatable:: QP_r_limits(:,:)
 !
 if (.not.allocated(QP_state)) then
   !
   !Input File -> QP_table
   !
   call PARSER_array(mode="INT dimensions",VAR="QPkrange",N=k_rng_lines,M=4)
   if (k_rng_lines>0) then
     YAMBO_ALLOC(QP_i_limits,(k_rng_lines,4))
     call PARSER_array(mode="read",VAR="QPkrange",N=k_rng_lines,M=4,I_v=QP_i_limits)
     do i1=1,k_rng_lines
       call i_check(QP_i_limits(i1,:2),en%nk)
       call i_check(QP_i_limits(i1,3:),en%nb)
     enddo
   endif
   !
   ! %QPerange fields
   !
   call PARSER_array(mode="REAL dimensions",VAR="QPerange",N=e_rng_lines,M=4)
   if (e_rng_lines>0) then
     YAMBO_ALLOC(QP_r_limits,(e_rng_lines,4))
     call PARSER_array(mode="read",VAR="QPerange",N=e_rng_lines,M=4,R_v=QP_r_limits)
     do i1=1,e_rng_lines
       QP_r_limits(i1,3:4)=QP_r_limits(i1,3:4)/HA2EV
       v=int(QP_r_limits(i1,:2))
       call i_check(v,en%nk)
       QP_r_limits(i1,:2)=real(v,SP)
     enddo
   endif
   !
   ! Non null %QPerange/%QPkrange fields
   !
   if (.not.all((/k_rng_lines==0,e_rng_lines==0/))) then
     !
     ! QP_nk setup
     !
     QP_k_nk=0
     QP_e_nk=0
     if (k_rng_lines>0) QP_k_nk=    maxval(QP_i_limits(:,1:2))
     if (e_rng_lines>0) QP_e_nk=int(maxval(QP_r_limits(:,1:2)))
     if (max(QP_k_nk,QP_e_nk)>0) QP_nk=max(QP_k_nk,QP_e_nk)
     !
     ! QP_nb setup
     !
     QP_k_nb=0
     QP_e_nb=0
     if (k_rng_lines>0) QP_k_nb=maxval(QP_i_limits(:,3:4))
     if (allocated(en%E)) then
       do i1=1,e_rng_lines
         do ik=int(QP_r_limits(i1,1)),int(QP_r_limits(i1,2)),1
           do ib=1,en%nb
             if (en%E(ib,ik,1)<QP_r_limits(i1,4)) QP_e_nb=max(QP_e_nb,ib)
           enddo
         enddo
       enddo
     endif
     if ( max(QP_k_nb,QP_e_nb)>0) QP_nb=max(QP_k_nb,QP_e_nb)
     !
     ! QP_state setup
     !
     YAMBO_ALLOC(QP_state,(QP_nb,QP_nk))
     QP_state(:,:)=.false.
     do i1=1,k_rng_lines
       QP_state(QP_i_limits(i1,3):QP_i_limits(i1,4),QP_i_limits(i1,1):QP_i_limits(i1,2))=.true.
     enddo
     if (allocated(en%E)) then
       do i1=1,e_rng_lines
         do ik=int(QP_r_limits(i1,1)),int(QP_r_limits(i1,2)),1
           do ib=1,en%nb
             if (all((/QP_r_limits(i1,3)<=en%E(ib,ik,1),&
&                      en%E(ib,ik,1)<=QP_r_limits(i1,4)/))) QP_state(ib,ik)=.true.
           enddo
         enddo
       enddo
     endif
     !
   else
     !
     if (.not.allocated(en%E)) return
     YAMBO_ALLOC(QP_state,(QP_nb,QP_nk))
     QP_state(:,:)=.true.
     !
   endif
   !
   YAMBO_FREE(QP_i_limits)
   YAMBO_FREE(QP_r_limits)
   !
 endif
 !
 ! Band Mixing
 !=============
 !
 ! Note: only upper triangle of the table is filled. 
 !       This corresponds to assume symmetric/hermitian 
 !       matrixes
 !
 ! Note (2) : a non zero mixing is allowed only in a SC/RT calculation
 !
 bands_mixed   =1
 SC_bands_mixed=1
 !
 Mixing=.FALSE.
#if defined _SC || defined _RT
 Mixing=l_sc_run.or.l_real_time.or.l_eval_collisions.or.l_nl_optics
 if (l_eval_collisions) Mixing=l_elel_scatt.or.(index(H_potential,"FOCK")>0.and.index(H_potential,"HARTREE")>0)&
&                                          .or.trim(H_potential)=="COHSEX"
#endif
 !
 if (Mixing) then
   !
#if !defined _ELPH
   if (any(.not.QP_state(1,:)).or.any(.not.QP_state(QP_nb,:))) SC_band_mixing=0._SP
#endif
   !
   if (SC_band_mixing<0._SP.or.SC_band_mixing>100._SP) SC_band_mixing=0._SP
   if (SC_band_mixing>0._SP) SC_bands_mixed=nint(QP_nb*SC_band_mixing/100._SP)
   if (SC_bands_mixed==0) SC_bands_mixed=1
   !
   ! Recalculated SC/RT band mixing
   !
   SC_band_mixing=float(SC_bands_mixed)*100._SP/float(QP_nb)
   bands_mixed=SC_bands_mixed
   !
 endif
 !
 ! QP_table allocation
 !
 QP_n_states=product(shape(pack(QP_state,QP_state)))*(2*bands_mixed-1)
 QP_n_states=QP_n_states*n_sp_pol
 !
 if (.not.allocated(QP_table)) then
   YAMBO_ALLOC(QP_table,(QP_n_states,3+n_sp_pol-1))
   QP_table=0
 endif
 !
 QP_n_states=0
 !
 do i1=1,QP_nk
   do i2=1,QP_nb
     !
     if (.not.QP_state(i2,i1)) cycle
     !
     do i_sp=1,n_sp_pol
       do i3=0,bands_mixed-1
         !
         if (i2+i3>QP_nb.or.i2+i3<1) cycle
         !
#if defined _SC || defined _RT
         if ((l_sc_run.or.l_real_time) .and. (i2<H_ref_bands(1)) ) cycle
#endif
#if defined _SC
         if (l_sc_run .and. (l_SC_diagonal.and.i3/=0) ) cycle
#endif
         !
         QP_n_states=QP_n_states+1
         QP_table(QP_n_states,1)=i2
         QP_table(QP_n_states,2)=i2+i3
         QP_table(QP_n_states,3)=i1
         if (n_sp_pol==2) QP_table(QP_n_states,4)=i_sp
         !
         !
       enddo
     enddo
   enddo
 enddo
 !
 contains
   !
   subroutine i_check(k_i,ilim)
     integer :: k_i(2),ilim
     if (k_i(1)>ilim.or.k_i(1)<1) k_i(1)=1
     if (k_i(2)>ilim.or.k_i(2)<1) k_i(2)=ilim
     if (k_i(1)>k_i(2)) k_i(1)=1
   end subroutine
   !
end subroutine

!
! License-Identifier: GPL
!
! Copyright (C) 2007 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DS
!
subroutine K_inversion_driver(iq,W,E,k,q) 
 !
 use pars,           ONLY:SP
 use X_m,            ONLY:Resp_ii,X_OUTPUT_driver
 use BS_solvers,     ONLY:BSS_inversion_mode,BSS_desc,K_INV_PL,K_INV_EPS,&
&                         K_Inversion_data,K_slk,K_inv_slk
 use BS,             ONLY:BS_H_dim,BS_Blocks_symmetrize_K,BS_blk,l_BS_ares_from_res,&
&                         BS_K_anti_resonant,l_BS_photolum,BS_res_ares_n_mat
 use electrons,      ONLY:levels
 use frequency,      ONLY:w_samp
 use R_lattice,      ONLY:bz_samp
 use com,            ONLY:isec,msg
 use LIVE_t,         ONLY:live_timing
 use parallel_int,   ONLY:PP_wait,PP_redux_wait,PARALLEL_index,PARALLEL_live_message
 use parallel_m,     ONLY:PP_indexes,PP_indexes_reset,PAR_COM_SLK_INDEX_local,PAR_COM_SLK_INDEX_local
 use IO_int,         ONLY:io_control
 use IO_m,           ONLY:REP,NONE,OP_WR_CL
 use matrix,         ONLY:MATRIX_reset
 use timing_m,       ONLY:timing
#if defined _SCALAPACK
 use interfaces,     ONLY:MATRIX_transfer,MATRIX_duplicate
 use parallel_m,     ONLY:linear_algebra_is_parallel
#endif
#if defined _RT
 use RT_control,     ONLY:NEQ_Residuals,NEQ_Kernel
#endif
 use stderr,         ONLY:intc
 use descriptors,    ONLY:IO_desc_add
 use PHOTOLUM,       ONLY:BSS_PL_free,PL
 !
#include<y_memory.h>
 !
 type(w_samp) :: W
 integer      :: iq
 type(levels) :: E
 type(bz_samp):: k,q
 !
 ! Work Space...
 !
 ! ... dummies
 !
 type(PP_indexes)  :: PAR_IND_freqs
 integer           :: i1,i2,iw,PAR_IND_FREQ_ID
 logical, external :: STOP_now
 real(SP)          :: ratio
 character(1)      :: sec
 complex(SP), allocatable :: Lo(:,:,:)
 !
 ! ... frequencies
 !
 integer    ::nw,nw_conv
 logical    ::FULL,PERTURBATIVE,completed
 !
 ! I/O
 !
 integer           :: i_err,ID,Lo_dim,Lo_n_loop
 integer, external :: io_BSS_invert
 !
 if (BS_res_ares_n_mat>1) then
   call warning(" inversion solver coding not finalized for case with two BSE matricies ")
   return
 endif
 !
 call timing('Inversion Solver',OPR='start')
 !
 ! Sectioning
 !============
 if (isec(2)/=0) sec="="
 if (isec(2)==0) sec="+"
 call section(sec,'Inversion Solver @q'//trim(intc(iq)))
 !
#if defined _SCALAPACK
 !
 ! Symmetrize the K blocks (to be eventually sent to the BLACS)
 !=========================
 if (linear_algebra_is_parallel) call BS_Blocks_symmetrize_K()
 !
#endif
 !
 ! Restart database
 !==================
 call K_inversion_restart(iq,W)
 !
 completed=count(K_INV_EPS%err/=0)==0
 if(l_BS_photolum) completed=completed.and.count(K_INV_PL%err/=0)==0
 if (completed) then
   call LOCAL_clean()
   return
 endif
 !
 ! Full inversion ?
 !==================
 FULL         = index(BSS_inversion_mode,'f')/=0
 PERTURBATIVE = index(BSS_inversion_mode,'p')/=0
 !
#if defined _RT
 if (NEQ_Residuals.neqv.NEQ_Kernel) then
   call warning("[INV] Different occupation configurations for Kernel and Residuals not supported")
 endif
#endif
 !
#if defined _SCALAPACK
 ! 
 ! SLK matrix initialization before the Kernel loading
 !
 call MATRIX_init( "SLK", K_slk, BS_H_dim, 1 )
 !
 YAMBO_ALLOC(K_slk%blc,(K_slk%BLCrows(1):K_slk%BLCrows(2),K_slk%BLCcols(1):K_slk%BLCcols(2),1))
 !
#endif
 !
 ! Kernel and/or BSS components loading
 !======================================
 call K_components_folded_in_serial_arrays(iq)
 !
 if (K_slk%kind=="SLK") then
   !
#if defined _SCALAPACK
   !
   call msg('rs','[LA] BLACS matrix filling')
   !
   ! Prepare the BLACS matrices (reference, K_slk and local, K_inv_slk)
   !============================
   !
   call MATRIX_transfer(M_out=K_slk, M_bse= BS_blk )
   !
   ! Diagonal removal
   !==================
   call K_diagonal(iq,"rm_OCC DIAG")
   !
   if (FULL) call MATRIX_duplicate( "none", M_in=K_slk, M_out=K_inv_slk )
   !
#endif
   !
 else
   !
   call K_stored_in_a_big_matrix(1,iq,"INV")
   !
   ! Diagonal removal
   !==================
   call K_diagonal(iq,"rm_E rm_OCC DIAG")
   !
 endif
 !
 ! IP-part Lo [also recompute Resp_xx(:,3) OR PL (needed in case of DbG)]
 !===========================================================================
 Lo_dim=1
 if (BS_K_anti_resonant.and.l_BS_ares_from_res) Lo_dim=2
 Lo_n_loop=Lo_dim
 !
 ! In the PL case we need, in addition to the standard GF, also some additional L_k^(r)(w) A_k(w) L_k^(a)(w), where
 ! L^(a/r) are deduced from the standard components.
 !
 if (l_BS_photolum) then
   Lo_dim=2
   if (BS_K_anti_resonant.and.l_BS_ares_from_res) Lo_dim=4
 endif
 !
 YAMBO_ALLOC(Lo,(BS_H_dim,W%n_freqs,Lo_dim))
 !
 call K_inversion_Lo(iq,W,E,k,Lo_dim,Lo_n_loop,Lo)
 !
 ! Initialize & write the output file 
 !====================================
 call X_OUTPUT_driver("DEF INIT",solver="Inversion") 
 call K_OUTPUT(iq,W,"open Inversion close","ALL")
 !
 ! Perturbative Inversion
 !========================
 call PP_indexes_reset(PAR_IND_freqs)
 PAR_IND_FREQ_ID=PAR_COM_SLK_INDEX_local%CPU_id+1
 !
 if (PERTURBATIVE) then
   !
   call PARALLEL_index(PAR_IND_freqs,(/W%n_freqs/),COMM=PAR_COM_SLK_INDEX_local)
   call PARALLEL_live_message('Perturbative Inversion Frequencies',LOADED=PAR_IND_freqs%n_of_elements(PAR_IND_FREQ_ID),&
&                              TOTAL=W%n_freqs,NCPU=PAR_COM_SLK_INDEX_local%n_CPU)
   call live_timing('Perturbative inversion ',PAR_IND_freqs%n_of_elements(PAR_IND_FREQ_ID))
   !
   call K_inversion_engine("any",1,W%n_freqs,PAR_IND_freqs,W,Lo,Lo_dim,Lo_n_loop,.FALSE.)
   !
   call PP_redux_wait(K_INV_EPS%err,COMM=PAR_COM_SLK_INDEX_local%COMM)
   call PP_redux_wait(Resp_ii(:,2),COMM=PAR_COM_SLK_INDEX_local%COMM)
   if (l_BS_photolum) then
     call PP_redux_wait(K_INV_PL%err,COMM=PAR_COM_SLK_INDEX_local%COMM)
     call PP_redux_wait(PL(:,2),COMM=PAR_COM_SLK_INDEX_local%COMM)
   endif
   !
   ! I/O [after pert inversion]
   !
   K_INV_EPS%spectra(:,1)=Resp_ii(:,2)
   if (l_BS_photolum) then
     K_INV_PL%spectra(:,1)=PL(:,2)
     !
     call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1,2,3,4/),ID=ID)
     i_err=io_BSS_invert(iq,W,ID)
     call msg('rs','[PERTURBATIVE INV@PL ] Converged frequencies ',count(K_INV_PL%err==0))
   else
     call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1,2,3/),ID=ID)
     i_err=io_BSS_invert(iq,W,ID)
     call msg('rs','[PERTURBATIVE INV@EPS] Converged frequencies ',count(K_INV_EPS%err==0))
   endif
   !
 endif
 !
 call K_OUTPUT(iq,W,"override dump Inversion close","ALL")
 !
 ! Full Inversion
 !=================
 !
 ! First I define the group of frequencies not converged
 !
 if (FULL) then
   !======
   call FULL_INF_freqs(K_INV_EPS)
   if (l_BS_photolum) call FULL_INF_freqs(K_INV_PL)
   !
 endif
 !
 if (FULL.and.PERTURBATIVE) then
   !==============
   !
   call FULL_INF_pre_setup(K_INV_EPS)
   if (l_BS_photolum) call FULL_INF_pre_setup(K_INV_PL)
   !
 endif
 !
 ! FULL INVERSION
 !================
 !
 if (K_INV_EPS%n_full_inv_freqs>0.and.FULL) call do_it_FULL(K_INV_EPS)
 if (l_BS_photolum) then
   if (K_INV_PL%n_full_inv_freqs>0.and.FULL) call do_it_FULL(K_INV_PL)
 endif
 !
 ! Try a polinomial interpolation on the null values (only for EPS)
 !==================================================================
 call K_eps_interpolate(W%n_freqs,real(W%p),K_INV_EPS%err)
 !
 call PP_wait()
 !
 ! I/O [after full inversion]
 !=====
 K_INV_EPS%spectra(:,1)=Resp_ii(:,2)
 if (l_BS_photolum) K_INV_PL%spectra(:,1)=PL(:,2)
 !
 if (l_BS_photolum) then
   call io_control(ACTION=OP_WR_CL,COM=REP,SEC=(/1,2,3,4/),ID=ID)
   i_err=io_BSS_invert(iq,W,ID)
 else
   call io_control(ACTION=OP_WR_CL,COM=REP,SEC=(/1,2,3/),ID=ID)
   i_err=io_BSS_invert(iq,W,ID)
 endif
 !
 ! Final Output
 !==============
 !
 ratio=real(count(K_INV_EPS%err==0))/real(W%n_freqs)*100._SP
 !
 call IO_desc_add(BSS_desc,kind="r",str="[INV] Converged frequencies",term="o/o",R=(/ratio/))
 !
 call K_OUTPUT(iq,W,"override dump close Inversion","ALL")
 !
 ! CLEAN
 !
 call LOCAL_clean()
 !
 contains 
   !
   subroutine do_it_FULL(TYP)
     !
     type(K_Inversion_data) :: TYP
     !
     ! Then loop on the groups performing full inversion
     !
     call PP_indexes_reset(PAR_IND_freqs)
     call PARALLEL_index(PAR_IND_freqs,(/TYP%n_full_inv_freqs/),COMM=PAR_COM_SLK_INDEX_local)
     call PARALLEL_live_message('['//TYP%what//'] Exact Inversion Frequencies',LOADED=PAR_IND_freqs%n_of_elements(PAR_IND_FREQ_ID),&
&                               TOTAL=TYP%n_full_inv_freqs,NCPU=PAR_COM_SLK_INDEX_local%n_CPU)
     call live_timing('['//TYP%what//'] Exact inversion ',PAR_IND_freqs%n_of_elements(PAR_IND_FREQ_ID))
     !
     do i1=1,TYP%n_full_inv_freqs
       !
       if (.not.PAR_IND_freqs%element_1D(i1)) cycle
       !
       iw=TYP%iw_full(i1)
       !
       call K_inversion_engine(TYP%what,iw,1,PAR_IND_freqs,W,Lo,Lo_dim,Lo_n_loop,.TRUE.)
       !
       call live_timing(steps=1)
       !
       if (STOP_now(.FALSE.)) then
         exit
       endif
       !
     enddo
     !
     call live_timing()
     call PP_redux_wait(TYP%err,imode=2)
     if (TYP%what=="EPS") call PP_redux_wait(Resp_ii(:,2),COMM=PAR_COM_SLK_INDEX_local%COMM)
     if (TYP%what=="PLS") call PP_redux_wait(PL(:,2),COMM=PAR_COM_SLK_INDEX_local%COMM)
     !
     nw_conv=count(TYP%err==0)
     call msg('rs','[FULL INV@'//TYP%what//'] Frequencies DONE      ',nw_conv)
     call msg('rs','[FULL INV@'//TYP%what//']                       ',real(nw_conv)/real(W%n_freqs)*100._SP,"[o/o]")
     !
   end subroutine
   !
   subroutine FULL_INF_freqs(TYP)
     type(K_Inversion_data) :: TYP
     TYP%n_full_inv_freqs=0
     do i1=1,W%n_freqs
       if (TYP%err(i1)/=0) then
         TYP%n_full_inv_freqs=TYP%n_full_inv_freqs+1
         TYP%iw_full(TYP%n_full_inv_freqs)=i1
       endif
     enddo
   end subroutine
   !
   subroutine FULL_INF_pre_setup(TYP)
     !
     type(K_Inversion_data) :: TYP
     integer :: min_dist_non_conv_freqs ! Every W%n_freqs/min_dist_non_conv_freqs
     logical :: found
     !
     min_dist_non_conv_freqs=W%n_freqs
     found = .FALSE.
     !
     do while (.not.found) 
       !
       TYP%n_full_inv_freqs=0
       !
       iw=-1
       nw=0
       do i1=1,W%n_freqs
         if (TYP%err(i1)/= 0.and.iw<0) iw=i1
         if (TYP%err(i1)/= 0.and.iw>0) nw=nw+1
         if ((TYP%err(i1)== 0.or.(TYP%err(i1)/=0.and.i1==W%n_freqs)).and.iw>0) then
           !
           if (nw>=min_dist_non_conv_freqs) then
             !
             do i2=iw,iw+nw-1,min_dist_non_conv_freqs
               TYP%n_full_inv_freqs=TYP%n_full_inv_freqs+1
               TYP%iw_full(TYP%n_full_inv_freqs)=i2
             enddo
             !
           endif
           iw=-1
           nw=0
         endif
       enddo
       min_dist_non_conv_freqs=min_dist_non_conv_freqs-1
       if (min_dist_non_conv_freqs==0) found=.TRUE.
       !
       if (TYP%n_full_inv_freqs>=nint(real(W%n_freqs)/TYP%PERT_FULL_ratio)) found=.TRUE.
       !
     enddo
     !
     if (TYP%n_full_inv_freqs>0.and.FULL) then 
       if (TYP%what=="EPS") Resp_ii(:,2)=Resp_ii(:,2)/real(PAR_COM_SLK_INDEX_local%n_CPU,SP)
       if (TYP%what=="PLS") PL(:,2)=PL(:,2)/real(PAR_COM_SLK_INDEX_local%n_CPU,SP)
     endif
     !
     call msg('rs','[FULL INV@'//TYP%what//'] Frequencies TODO ',TYP%n_full_inv_freqs)
     !
   end subroutine
   !
   subroutine LOCAL_clean
     !
     if (l_BS_photolum) call BSS_PL_free( )
     !
     call LOCAL_TYP_clean(K_INV_EPS)
     if (l_BS_photolum) call LOCAL_TYP_clean(K_INV_PL)
     !
     call PP_indexes_reset(PAR_IND_freqs)
     YAMBO_FREE(Lo)
     !
#if defined _SCALAPACK
     YAMBO_FREE(K_slk%blc)
     call MATRIX_reset(K_slk)
     !
     ! Here I call MATRIX_duplicate instead of a simple YAMBO_FREE to keep the correct naming 
     ! to be used in the memory module
     !
     call MATRIX_duplicate( "free", M_out=K_inv_slk )
#endif
     !
     call timing('Inversion Solver',OPR='stop')
   end subroutine
   !
   subroutine LOCAL_TYP_clean(TYP)
     type(K_Inversion_data) :: TYP
     deallocate(TYP%err,TYP%spectra,TYP%iw_full)
   end subroutine
   !
end subroutine

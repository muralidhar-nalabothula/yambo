!
! License-Identifier: GPL
!
! Copyright (C) 2018 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
module interpolate_tools
 !
 use pars,         ONLY:SP,schlen,rZERO
 use interpolate,  ONLY:interpls,INTERP_obj,l_INTERP_dE,l_INTERP_E,l_INTERP_f,max_interpls,INTERP_mode,&
&                       l_INTERP_W,NN_nk_exact,NN_nk_border,NN_MAX_real_nearest,NN_n_of_nearest,l_INTERP_Z,&
&                       INTERPOLATE_msg_fmt,OUT_k_nk,INTERP_FineGd
 use electrons,    ONLY:n_sp_pol
 !
#include<y_memory.h>
 !  
 contains
   !
   subroutine INTERPOLATION_nearest_k_report(ID)
     !
     use com,   ONLY:msg
     !
     integer,      intent(in) :: ID
     !
     integer             :: IDs_todo(2),ID_
     real(SP)            :: dummy
     character(schlen)   :: title
     !
     if (ID==0) return
     if (ID< 0) IDs_todo=(/1,max_interpls/)
     if (ID> 0) IDs_todo=ID
     !
     do ID_=IDs_todo(1),IDs_todo(2)
       !
       if (.not.INTERP_obj(ID_)%in_use) return
       !
       title=trim(INTERP_obj(ID_)%what)//"-Nearest K"
       if (trim(INTERP_FineGd)/="NONE") title=trim(title)//"-"//trim(INTERP_FineGd)//" FineGd"
       !
       dummy=real(NN_nk_exact/real(OUT_k_nk))*100._SP
       call msg('n'//trim(INTERPOLATE_msg_fmt),'['//trim(title)//'] Exact matches       ',dummy,"[o/o]")
       if (NN_nk_border>0) then
          call msg('n'//trim(INTERPOLATE_msg_fmt),'['//trim(title)//'] Border points       ',NN_nk_border)
       endif
       if (NN_nk_exact<OUT_k_nk) then
         call msg(trim(INTERPOLATE_msg_fmt),'['//trim(title)//'] Neighbours    [user]',NN_n_of_nearest)
         call msg(trim(INTERPOLATE_msg_fmt),'['//trim(title)//']               [real]',NN_MAX_real_nearest)
         dummy=real(OUT_k_nk-NN_nk_exact)/real(OUT_k_nk)*100._SP
         call msg(trim(INTERPOLATE_msg_fmt),'['//trim(title)//'] Interpolations      ',dummy,"[o/o]")
       endif
       !
       OUT_k_nk=0
       NN_nk_exact=0
       NN_nk_border=0
       !
     enddo
     !
   end subroutine
   !
   subroutine INTERPOLATION_reset(ID)
     !
     integer, intent(in) :: ID
     !
     interpls(ID)%ndim=0
     interpls(ID)%interp_type=""
     if (allocated(interpls(ID)%engre)) deallocate(interpls(ID)%engre)
     INTERP_obj(ID)%nb=0
     INTERP_obj(ID)%nk=0
     INTERP_obj(ID)%D=0
     INTERP_obj(ID)%ID=0
     INTERP_obj(ID)%use_NN=.FALSE.
     INTERP_obj(ID)%in_use=.FALSE.
     INTERP_obj(ID)%seed_kind=" "
     INTERP_obj(ID)%what=" "
     INTERP_FineGd="NONE"
     YAMBO_FREE(INTERP_obj(ID)%k)
     YAMBO_FREE(INTERP_obj(ID)%weights)
     YAMBO_FREE(INTERP_obj(ID)%SEED)
     YAMBO_FREE(INTERP_obj(ID)%INTERP)
     !
   end subroutine
   !
   subroutine init_ID(ID,dims,k,operation,seed_kind)
     !
     use R_lattice,   ONLY:bz_samp
     !
     integer      , intent(in) :: ID,dims(2)
     type(bz_samp), intent(in) :: k
     character(*) , intent(in) :: operation,seed_kind
     !
     INTERP_obj(ID)%nb=dims
     INTERP_obj(ID)%nk=k%nibz
     INTERP_obj(ID)%in_use=.TRUE.
     INTERP_obj(ID)%use_NN=trim(INTERP_mode)=="NN"
     INTERP_obj(ID)%seed_kind=seed_kind
     INTERP_obj(ID)%what=operation
     !
     YAMBO_FREE(INTERP_obj(ID)%k)
     YAMBO_ALLOC(INTERP_obj(ID)%k,(k%nibz,3))
     INTERP_obj(ID)%k=k%pt
     !
     YAMBO_FREE(INTERP_obj(ID)%weights)
     YAMBO_ALLOC(INTERP_obj(ID)%weights,(k%nibz))
     INTERP_obj(ID)%weights=k%weights
     !
     YAMBO_FREE(INTERP_obj(ID)%SEED)
     YAMBO_ALLOC(INTERP_obj(ID)%SEED,(dims(1):dims(2),k%nibz,INTERP_obj(ID)%D))
     INTERP_obj(ID)%SEED=rZERO
     !
   end subroutine init_ID
   !
   subroutine get_ID(ID)
     !
     integer, intent(out) :: ID
     integer :: i1
     logical :: done
     !
     done=.false.
     i1=1
     !
     do while(.not.done.and.i1<max_interpls)
       if(interpls(i1)%ndim==0) then
         ID=i1
         done=.true.
       endif
       i1=i1+1
     enddo
     !
     if(.not.done) call error("Error too many simultaneous interpolations.")
     !
   end subroutine get_ID
   !
   subroutine make_star(R_vec,nsym,symop,nstar,star_vec)
     !
     use vec_operate,    ONLY:v_is_zero
     !
     implicit none
     !
     integer,  intent(in)   :: nsym
     real(SP), intent(in)   :: R_vec(3),symop(3,3,nsym) ! input vector and symmetry operations
     real(SP), intent(out)  :: star_vec(3,nsym)         ! star vectors - maximum number is nsym
     integer,  intent(out)  :: nstar                    ! number of vectors in star
     !
     ! Work Space
     !
     integer  :: i1,is
     logical  :: add_vec
     real(SP) :: try(3)
     !
     nstar=1
     star_vec(1:3,1)=R_vec(1:3)
     !
     do is=1,nsym 
       try(1:3)=matmul(symop(:,:,is),R_vec(:))
       add_vec=.TRUE.
       do i1=1,nstar
         if(v_is_zero(try(:)-star_vec(:,i1))) add_vec=.FALSE.
       enddo
       !
       if(add_vec) then
         nstar=nstar+1
         star_vec(1:3,nstar)=try(1:3)
       endif
     enddo
     !
  end subroutine make_star
  !
  subroutine FILL_SEED_E(ID,SEED_E)
    !
    use electrons, ONLY:levels
    !
    integer,      intent(in) :: ID
    type(levels), intent(in) :: SEED_E
    ! 
    integer :: i_s,ib,ik !WS
    !
    do i_s=1,n_sp_pol
      do ib=INTERP_obj(ID)%nb(1),INTERP_obj(ID)%nb(2)
       do ik=1,INTERP_obj(ID)%nk
          if (l_INTERP_f ) INTERP_obj(ID)%SEED(ib,ik,i_s)=SEED_E%f(ib,ik,i_s)
          if (l_INTERP_E ) INTERP_obj(ID)%SEED(ib,ik,i_s)=SEED_E%E(ib,ik,i_s)
          if (l_INTERP_dE) INTERP_obj(ID)%SEED(ib,ik,i_s)=SEED_E%E(ib,ik,i_s)-SEED_E%Eo(ib,ik,i_s)
        enddo
      enddo
    enddo
    !
  end subroutine
  !
#if defined _RT
  subroutine FILL_SEED_RT(ID,SEED_RT)
    !
    use real_time, ONLY:RT_t
    !
    integer,    intent(in) :: ID
    type(RT_t), intent(in) :: SEED_RT
    !
    integer :: i_RT,ib,ik,i_s !WS
    !
    do i_RT=1,SEED_RT%nstates
      !
      ib   =SEED_RT%table(i_RT,1)
      !
      if (ib<INTERP_obj(ID)%nb(1).or.ib>INTERP_obj(ID)%nb(2)) cycle
      !
      ik   =SEED_RT%table(i_RT,3)
      i_s  =SEED_RT%table(i_RT,4)
      if (l_INTERP_f ) INTERP_obj(ID)%SEED(ib,ik,i_s)=SEED_RT%OCC_el%dN(i_RT) 
      if (l_INTERP_W ) INTERP_obj(ID)%SEED(ib,ik,i_s)=SEED_RT%NEQ_Lifetime(i_RT) 
      if (l_INTERP_dE) INTERP_obj(ID)%SEED(ib,ik,i_s)=SEED_RT%delta_E(i_RT) 
      !
    enddo
    !
  end subroutine
#endif
  !
  subroutine FILL_SEED_QP(ID,SEED_QP)
    !
    use electrons, ONLY:spin
    use QP_m,      ONLY:QP_t
    !
    integer,    intent(in) :: ID
    type(QP_t), intent(in) :: SEED_QP
    !
    ! Work Space
    !
    integer :: i_qp,ib,ik,i_s,i_ref(4)
    !
    do i_qp=1,SEED_QP%n_states
      !
      ib   =SEED_QP%table(i_qp,1)
      !
      if (ib<INTERP_obj(ID)%nb(1).or.ib>INTERP_obj(ID)%nb(2)) cycle
      !
      ik   =SEED_QP%table(i_qp,3)
      i_s  =spin(SEED_QP%table(i_qp,:))
      !
      i_ref=0
      if (l_INTERP_E  ) i_ref(2)=n_sp_pol
      if (l_INTERP_dE ) i_ref(3)=i_ref(2)+n_sp_pol
      if (l_INTERP_W  ) i_ref(4)=i_ref(3)+n_sp_pol
      if (l_INTERP_E  ) then
        INTERP_obj(ID)%SEED(ib,ik,i_ref(1)+i_s)=real(SEED_QP%E(i_qp))
      endif
      if (l_INTERP_dE) then
        INTERP_obj(ID)%SEED(ib,ik,i_ref(2)+i_s)=real(SEED_QP%E(i_qp))-SEED_QP%E_bare(i_qp)
      endif
      if (l_INTERP_W ) then
        INTERP_obj(ID)%SEED(ib,ik,i_ref(3)+i_s)=aimag(SEED_QP%E(i_qp))
      endif
      if (l_INTERP_Z ) then
        INTERP_obj(ID)%SEED(ib,ik,i_ref(4)+i_s)=real(SEED_QP%Z(i_qp))
        INTERP_obj(ID)%SEED(ib,ik,i_ref(4)+n_sp_pol+i_s)=aimag(SEED_QP%Z(i_qp))
      endif
    enddo
    !
  end subroutine
  !
end module interpolate_tools

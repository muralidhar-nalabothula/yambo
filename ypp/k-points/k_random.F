!
! License-Identifier: GPL
!
! Copyright (C) 2016 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine k_random(Xk,No_Weight)
 !
 use pars,                ONLY:SP,DP,lchlen
 use com,                 ONLY:msg,of_open_close
 use vec_operate,         ONLY:c2a,k2bz
 use R_lattice,           ONLY:bz_samp,k_the_nearest,k_grid_b
 use YPPm,                ONLY:BZ_random_nkpts,K_transform
 use LIVE_t,              ONLY:live_timing
 use stderr,              ONLY:intc
 use parallel_m,          ONLY:PP_indexes,myid,PP_indexes_reset
 use parallel_int,        ONLY:PP_wait,PP_redux_wait,PARALLEL_index 
 use parser_m,            ONLY:parser 
 !
#include<y_memory.h>
 !
 type(bz_samp), intent(in) :: Xk
 logical, intent(in)       :: No_Weight
 !
 ! Work Space
 !
 real(SP), allocatable :: rand_k(:,:)
 integer,  allocatable :: MAP(:)
 integer               :: i_err,ik_near,i_count,i,j,k,ik_bz,i_cycle,N,ik_r,ic
 logical               :: bz_near_warning(1)
 character(lchlen)     :: k_rand_fname
 type(PP_indexes)      :: px
 logical               :: l_no_distribute
 !
 ! Random Generator
 !
 character(12)      :: ch(3)
 integer            :: iseed(8)
 real(DP), external :: dlaran
 integer            :: n_cycle
 !
 call date_and_time(ch(1),ch(2),ch(3),iseed)
 iseed=iabs(iseed)
 ! iseed(4) must be odd
 iseed(4)=2*(iseed(4)/2)+1
 !
 call parser('DoNotDistr',l_no_distribute)
 !
 call section('*',"== Random k-points generator ==")
 !
 ! ... ibz -> bz
 !
 ! ... Random points rounding & alloc
 N=int(real(BZ_random_nkpts)/real(Xk%nbz))*Xk%nbz
 if (N/=BZ_random_nkpts.and..not.l_no_distribute) then
   call warning("Random points adjusted to be BZ sampling compliant. New number of random points is "//trim(intc(N)))
   BZ_random_nkpts=N
 endif
 YAMBO_ALLOC(rand_k,(BZ_random_nkpts,3))
 !
 ! ...O file
 k_rand_fname="random_k_pts"
 call of_open_close(k_rand_fname,'ot')
 if (No_Weight     ) call msg('o random',"#",(/"c1","c2","c3"/),INDENT=0,USE_TABS=.true.)
 if (.not.No_Weight) call msg('o random',"#",(/"c1","c2","c3","wt"/),INDENT=0,USE_TABS=.true.)
 !
 call live_timing('Points maker',BZ_random_nkpts)
 !------------------------------------------------
 if(l_no_distribute) then
   !      
   do ik_r=1,BZ_random_nkpts
     !
     do ic=1,3
       rand_k(ik_r,ic)=(dlaran(iseed(4:))-1./2.)
     enddo
     !
     call c2a(v_in=rand_k(ik_r,:),mode="ka2i")
     call k2bz(v_in=rand_k(ik_r,:))
     call live_timing(steps=1)
     !
   enddo
   !
 else
   !      
   n_cycle=int(real(BZ_random_nkpts)/real(Xk%nbz))-1
   if(n_cycle<=0) call error(' Error too few random points comparared to the k-points number, increase BZ_random_Nk')
   !
   do i_cycle=0,n_cycle
     !
     do ik_bz=1,Xk%nbz
       !
       i_count=i_cycle*Xk%nbz+ik_bz
       !
       call build_3D_k( Xk%ptbz(ik_bz,:), rand_k(i_count,:) )
       !
       call live_timing(steps=1)
       !
     enddo
     !
   enddo
   !
 endif
 !
 call live_timing( )
 !
 !DEBUG-AM>
 ! ... Expand
 !call rand_k_expand( )
 !DEBUG-AM<
 !
 ! ... parallel setup
 call PP_indexes_reset(px)
 call PARALLEL_index(px,(/BZ_random_nkpts/))
 call PP_wait()
 !
 ! ... Map
 YAMBO_ALLOC(MAP,(Xk%nbz))
 MAP=0
 call live_timing('BZ Map',px%n_of_elements(myid+1))
 bz_near_warning=.FALSE.
 !
 do i_count=1,BZ_random_nkpts
   !
   ik_bz=mod(i_count,Xk%nbz)
   if (ik_bz==0) ik_bz=Xk%nbz
   !
   if (.not.px%element_1D(i_count)) cycle
   !
   ik_near = k_the_nearest(rand_k(i_count,:),Xk%ptbz(:,:),Xk%nbz,ROTATE_k_ref=.FALSE.,i_err=i_err)
   ik_near=iabs(ik_near)
   MAP(ik_near)=MAP(ik_near)+1
   if (ik_near/=ik_bz)  bz_near_warning=.TRUE.
   !
   call live_timing(steps=1)
   !
 enddo
 call live_timing( )
 call PP_redux_wait(MAP)
 !
 call msg("s","Min-Max BZ grid filling",(/minval(MAP),maxval(MAP)/))
 if (bz_near_warning(1).and..not.l_no_distribute) &
&      call warning("BZ grid and the Random grid are disaligned. (Eventually) try running again.")
 !
 ! ... Print
 call print_k( )
 !
 ! Clean & Close
 YAMBO_FREE(rand_k)
 YAMBO_FREE(MAP)
 call of_open_close(k_rand_fname)
 call live_timing()
 !
 contains
   !
   subroutine print_k()
     real(SP)           ::r(3)
     integer            :: ic
     do ic=1,BZ_random_nkpts
       call K_transform(rand_k(ic,:),'iku')
       r=rand_k(ic,:)
       if (     NO_Weight) call msg('o random',"",r,USE_TABS=.true.)
       if (.not.NO_Weight) call msg('o random',"",(/r(1),r(2),r(3),1._SP/),USE_TABS=.true.)
     enddo
   end subroutine
   !
   subroutine build_3D_k(k,r)
     real(DP), external :: dlaran
     real(SP)           :: k(3),r(3)
     integer            :: ic
     do ic=1,3
       r(ic)=(dlaran(iseed(4:))-1./2.)
     enddo
     call c2a(v_in=r,mode="ka2i",b_in=k_grid_b)
     call k2bz(v_in=r,b_in=k_grid_b)
     r=r+k
     call k2bz(v_in=r)
   end subroutine
   !
   subroutine rand_k_expand()
     integer ::i,j,k,N,ic,is
     real(SP)::r_save(BZ_random_nkpts,3)
     r_save=rand_k
     YAMBO_FREE(rand_k)
     N=BZ_random_nkpts*8
     YAMBO_ALLOC(rand_k,(N,3))
     ic=0
     do is=1,BZ_random_nkpts
       do i=1,-1,-2
         do j=1,-1,-2
           do k=1,-1,-2
             ic=ic+1
             rand_k(ic,:)=(/i*r_save(is,1),j*r_save(is,2),k*r_save(is,3)/)
           enddo
         enddo
       enddo
     enddo
     BZ_random_nkpts=ic
     !
   end subroutine
   !
end subroutine

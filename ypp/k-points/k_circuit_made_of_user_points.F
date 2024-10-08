! 
! License-Identifier: GPL
!
! Copyright (C) 2020 The Yambo Team
!
! Authors (see AUTHORS file for details): DS CA AM
!
subroutine k_circuit_made_of_user_points( )
 !
 use pars,           ONLY:SP,schlen
 use com,            ONLY:msg
 use vec_operate,    ONLY:c2a,v_norm
 use parser_m,       ONLY:PARSER_array
 use YPPm,           ONLY:BANDS_steps,USER_k,CIRCUIT_k,coo_in,coo_out,K_transform,PROJECT_mode
 !
#include<y_memory.h>
 !
 ! Work space
 !
 character(schlen)     :: coo_out_
 real(SP)              :: max_dist,v(3)
 real(SP), allocatable :: distances(:)
 integer               :: ik,ic,i1
 integer,  allocatable :: int_distances(:)
 !
 ! Read the kpts from input (extrema from the path)
 ! 
 USER_k%nbz=1
 call PARSER_array(mode="REAL dimensions",VAR="BANDS_kpts",N=USER_k%nbz,M=3)
 if (USER_k%nbz>0) then
   YAMBO_ALLOC(USER_k%pt,(USER_k%nbz,3))
   call PARSER_array(mode="read",VAR="BANDS_kpts",N=USER_k%nbz,M=3,R_v=USER_k%pt)
 endif
 USER_k%nibz=USER_k%nbz
 !
 if (USER_k%nbz==0) return
 !
 coo_out_=coo_out
 coo_out ="iku"
 do ik=1,USER_k%nbz
   call K_transform(USER_k%pt(ik,:),coo_in)
 enddo
 coo_out =coo_out_
 !
 ! Generate the circuit
 !======================
 !
 allocate(distances(USER_k%nbz-1),int_distances(USER_k%nbz-1))
 !
 do ik=1,USER_k%nbz-1
    v=USER_k%pt(ik,:)-USER_k%pt(ik+1,:)
    call c2a(v_in=v,mode="ki2c")
    distances(ik)=v_norm(v)
 enddo
 !
 max_dist=maxval(distances)
 !
 int_distances=BANDS_steps
 if (trim(PROJECT_mode)=="none") then
   do ik=1,USER_k%nbz-1
     int_distances(ik)=maxval((/nint(BANDS_steps*distances(ik)/max_dist),1/))
   enddo
 endif
 !
 CIRCUIT_k%nbz =sum(int_distances)+1
 CIRCUIT_k%nibz=CIRCUIT_k%nbz
 !
 call msg("s",'Number of Q/K-points in the circuit :',CIRCUIT_k%nbz)
 !
 YAMBO_ALLOC(CIRCUIT_k%pt,(CIRCUIT_k%nbz,3))
 YAMBO_ALLOC(CIRCUIT_k%weights,(CIRCUIT_k%nbz))
 !
 CIRCUIT_k%weights=1._SP/real(CIRCUIT_k%nbz,SP)
 !
 ic=1
 do ik=1,USER_k%nbz-1
   v=(USER_k%pt(ik+1,:)-USER_k%pt(ik,:))/int_distances(ik)
   do i1=1,int_distances(ik)
     CIRCUIT_k%pt(ic,:)= USER_k%pt(ik,:)+(i1-1._SP)*v
     ic=ic+1
   enddo
 enddo
 CIRCUIT_k%pt(CIRCUIT_k%nbz,:)=USER_k%pt(USER_k%nbz,:)
 !
 deallocate(distances,int_distances)
 !
end subroutine k_circuit_made_of_user_points

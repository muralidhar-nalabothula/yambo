!
! License-Identifier: GPL
!
! Copyright (C) 2010 The Yambo Team
!
! Authors (see AUTHORS file for details): CA AF AM
!
module wrapper_omp
 !
 ! To remember:
 !
 ! TRANSA = 'N' or 'n',  op( A ) = A.
 ! TRANSA = 'T' or 't',  op( A ) = A'.
 ! TRANSA = 'C' or 'c',  op( A ) = conjg( A' ).
 !
 use pars,    ONLY:DP,SP,cZERO,cONE,cZERO_DP,cONE_DP
 use wrapper, ONLY:V_copy,MM_caxpy,vv_c,vv_s,Vstar_dot_V,V_dot_V
 use openmp,  ONLY:n_threads_now
 !
 implicit none
 !
 interface M_by_M_omp
#if defined _DOUBLE
   module procedure mm_cgemm_omp,mm_c_omp
#else
   module procedure mm_cgemm_omp,mm_c_omp,mm_c_omp_DP
#endif
 end interface
 !
 interface M_by_V_omp
   module procedure mv_cgemv_omp,mv_sgemv_omp,mv_c_omp,mv_r_omp
 end interface
 !
 interface V_plus_alpha_V_omp
   module procedure vv_saxpy_omp,vv_caxpy_omp
 end interface
 !
 interface M_plus_alpha_M_omp
   module procedure MM_caxpy_omp
 end interface
 !
 interface V_dot_V_omp
   module procedure V_dot_V_r1_omp, V_dot_V_c1_omp, V_dot_V_c2_omp
 end interface
 !
 interface Vstar_dot_V_omp
   module procedure V_dot_V_r1_omp, Vstar_dot_V_c1_omp, Vstar_dot_V_c2_omp
 end interface
 !
 public :: V_copy_omp
 public :: Vstar_dot_V_omp
 public :: V_dot_V_omp
 public :: M_by_V_omp
 !
 contains
   !
   !===================
   ! interface M_by_M 
   !===================
   !
   subroutine mm_cgemm_omp(TRANSA,TRANSB,M,N,K,ALPHA,A,LDA,B,LDB,BETA,C,LDC)
     complex(SP), intent(in)  :: ALPHA,BETA
     integer,     intent(in)  :: K,LDA,LDB,LDC,M,N
     character,   intent(in)  :: TRANSA,TRANSB
     complex(SP), intent(in)  :: A(LDA,*),B(LDB,*)
     complex(SP), intent(out) :: C(LDC,*)
#if defined _OPENMP_INT_LINALG && defined _DOUBLE
     call ZGEMM_omp(TRANSA,TRANSB,M,N,K,ALPHA,A,LDA,B,LDB,BETA,C,LDC)
#elif defined _OPENMP_INT_LINALG && !defined _DOUBLE
     call CGEMM_omp(TRANSA,TRANSB,M,N,K,ALPHA,A,LDA,B,LDB,BETA,C,LDC)
#elif defined _DOUBLE
     call ZGEMM(TRANSA,TRANSB,M,N,K,ALPHA,A,LDA,B,LDB,BETA,C,LDC)
#else
     call CGEMM(TRANSA,TRANSB,M,N,K,ALPHA,A,LDA,B,LDB,BETA,C,LDC)
#endif
   end subroutine mm_cgemm_omp
   !
#if !defined _DOUBLE
   subroutine mm_c_omp_DP(TRANSA,TRANSB,msize,A,B,C)
     integer,  intent(in)  :: msize
     complex(DP), intent(in)  :: A(msize,msize),B(msize,msize)
     complex(DP), intent(out) :: C(msize,msize)
     character,   intent(in)  :: TRANSA,TRANSB
     !
     !
#if defined _OPENMP_INT_LINALG
     call ZGEMM_omp(TRANSA,TRANSB,msize,msize,msize,cONE_DP,A,msize,B,msize,cZERO_DP,C,msize)
#else
     call ZGEMM(TRANSA,TRANSB,msize,msize,msize,cONE_DP,A,msize,B,msize,cZERO_DP,C,msize)
#endif
   end subroutine mm_c_omp_DP
#endif
   !
   subroutine mm_c_omp(TRANSA,TRANSB,msize,A,B,C)
     integer,  intent(in)  :: msize
     complex(SP), intent(in)  :: A(msize,msize),B(msize,msize)
     complex(SP), intent(out) :: C(msize,msize)
     character,   intent(in)  :: TRANSA,TRANSB
     !
#if defined _OPENMP_INT_LINALG && defined _DOUBLE
     call ZGEMM_omp(TRANSA,TRANSB,msize,msize,msize,cONE,A,msize,B,msize,cZERO,C,msize)
#elif defined _OPENMP_INT_LINALG && !defined _DOUBLE
     call CGEMM_omp(TRANSA,TRANSB,msize,msize,msize,cONE,A,msize,B,msize,cZERO,C,msize)
#elif defined _DOUBLE
     call ZGEMM(TRANSA,TRANSB,msize,msize,msize,cONE,A,msize,B,msize,cZERO,C,msize)
#else
     call CGEMM(TRANSA,TRANSB,msize,msize,msize,cONE,A,msize,B,msize,cZERO,C,msize)
#endif
   end subroutine mm_c_omp
   !
   !===================
   ! interface M_by_V 
   !===================
   !
   subroutine mv_sgemv_omp(TRANS,M,N,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
     real(SP), intent(in) :: ALPHA,BETA
     integer,  intent(in) :: INCX,INCY,LDA,M,N
     character,intent(in) :: TRANS
     real(SP), intent(in) :: A(LDA,*),X(*)
     real(SP), intent(out):: Y(*)
#if defined _OPENMP_INT_LINALG && defined _DOUBLE
     call DGEMV_omp(TRANS,M,N,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
#elif defined _OPENMP_INT_LINALG && !defined _DOUBLE
     call SGEMV_omp(TRANS,M,N,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
#elif defined _DOUBLE
     call DGEMV(TRANS,M,N,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
#else
     call SGEMV(TRANS,M,N,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
#endif
   end subroutine mv_sgemv_omp
   !
   subroutine mv_cgemv_omp(TRANS,M,N,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
     complex(SP), intent(in) :: ALPHA,BETA
     integer,     intent(in) :: INCX,INCY,LDA,M,N
     character,   intent(in) :: TRANS
     complex(SP), intent(in) :: A(LDA,*),X(*)
     complex(SP), intent(out):: Y(*)
#if defined _OPENMP_INT_LINALG && defined _DOUBLE
     call ZGEMV_omp(TRANS,M,N,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
#elif defined _OPENMP_INT_LINALG && !defined _DOUBLE
     call CGEMV_omp(TRANS,M,N,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
#elif defined _DOUBLE
     call ZGEMV(TRANS,M,N,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
#else
     call CGEMV(TRANS,M,N,ALPHA,A,LDA,X,INCX,BETA,Y,INCY)
#endif
   end subroutine mv_cgemv_omp
   !
   subroutine mv_c_omp(TRANS,msize,A,X,Y)
     integer,     intent(in) :: msize
     complex(SP), intent(in) :: A(msize,*),X(*)
     complex(SP), intent(out):: Y(*)
     character,   intent(in) :: TRANS
#if defined _OPENMP_INT_LINALG && defined _DOUBLE
     call ZGEMV_omp(TRANS,msize,msize,cONE,A,msize,X,1,cZERO,Y,1)
#elif defined _OPENMP_INT_LINALG && !defined _DOUBLE
     call CGEMV_omp(TRANS,msize,msize,cONE,A,msize,X,1,cZERO,Y,1)
#elif defined _DOUBLE
     call ZGEMV(TRANS,msize,msize,cONE,A,msize,X,1,cZERO,Y,1)
#else
     call CGEMV(TRANS,msize,msize,cONE,A,msize,X,1,cZERO,Y,1)
#endif
   end subroutine mv_c_omp
   !
   subroutine mv_r_omp(TRANS,msize,A,X,Y)
     integer,  intent(in) :: msize
     real(SP), intent(in) :: A(msize,*),X(*)
     real(SP), intent(out):: Y(*)
     character,intent(in) :: TRANS
#if defined _OPENMP_INT_LINALG && defined _DOUBLE
     call DGEMV_omp(TRANS,msize,msize,1._SP,A,msize,X,1,0._SP,Y,1)
#elif defined _OPENMP_INT_LINALG && !defined _DOUBLE
     call SGEMV_omp(TRANS,msize,msize,1._SP,A,msize,X,1,0._SP,Y,1)
#elif defined _DOUBLE
     call DGEMV(TRANS,msize,msize,1._SP,A,msize,X,1,0._SP,Y,1)
#else
     call SGEMV(TRANS,msize,msize,1._SP,A,msize,X,1,0._SP,Y,1)
#endif
   end subroutine mv_r_omp
   !
   !=========================
   ! interface M_plus_alpha_M_omp
   !=========================
   !
   subroutine MM_caxpy_omp(N, CA, CX,  CY )
     complex(SP), intent(in) :: CA
     integer,     intent(in) :: N
     complex(SP), intent(in) :: CX(N,N)
     complex(SP), intent(out):: CY(N,N)
     !
#if defined _OPENMP_INT_LINALG 
     integer :: i,j
     if (n_threads_now>1) then
       !$omp parallel do default(shared), private(i,j)
       do j=1,N
         do i=1,N
           CY(i,j) = CY(i,j) + CA * CX(i,j)
         enddo
       enddo
       !$omp end parallel do
     else
       call MM_caxpy(N, CA, CX,  CY )
     endif
     !
#else
    call MM_caxpy(N, CA, CX,  CY )
#endif
   end subroutine MM_caxpy_omp
   !
   !=========================
   ! interface V_plus_alpha_V_omp
   !=========================
   !
   subroutine vv_caxpy_omp(N, CA, CX,  CY )
     complex(SP), intent(in) :: CA
     integer,     intent(in) :: N
     complex(SP), intent(in) :: CX(:)
     complex(SP), intent(out):: CY(:)
     !
#if defined _OPENMP_INT_LINALG
     integer :: i
     if (n_threads_now>1) then
       !$omp parallel do default(shared), private(i)
       do i=1,N
          CY(i) = CY(i) + CA * CX(i)
       enddo
       !$omp end parallel do
     else
       call vv_c(N, CA, CX,  CY )
     endif
     !
#else
     call vv_c(N, CA, CX,  CY )
#endif
   end subroutine vv_caxpy_omp
   !
   subroutine vv_saxpy_omp(N, CA, CX, CY )
     real(SP),    intent(in) :: CA
     integer,     intent(in) :: N
     real(SP),    intent(in) :: CX(:)
     real(SP),    intent(out):: CY(:)
     !
#if defined _OPENMP_INT_LINALG
     integer :: i
     if (n_threads_now>1) then
       !$omp parallel do default(shared), private(i)
       do i=1,N
         CY(i) = CY(i) + CA * CX(i)
       enddo
       !$omp end parallel do
     else
       call vv_s(N, CA, CX,  CY )
     endif
     !
#else
     call vv_s(N, CA, CX,  CY )
#endif
   end subroutine vv_saxpy_omp   
   !
   !======
   ! COPY 
   !======
   !
   subroutine V_copy_omp(N,CX,CY)
     integer,    intent(in)  :: N
     complex(SP),intent(in)  :: CX(:)
     complex(SP),intent(out) :: CY(:)
     !
#if defined _OPENMP_INT_LINALG
     integer :: i
     if (n_threads_now>1) then
       !$omp parallel do default(shared), private(i)
       do i=1,N
         CY(i)=CX(i)
       enddo
       !$omp end parallel do
     else
       call V_copy(N,CX,CY)
     endif
#else
     call V_copy(N,CX,CY)
#endif
     !
   end subroutine V_copy_omp   
   !
   !==============
   ! DOT PRODUCTS
   !==============
   !
   complex(SP) function Vstar_dot_V_c1_omp(N,CX,CY)
     integer,    intent(in) :: N
     complex(SP),intent(in) :: CX(:),CY(:)
     !
#if defined _OPENMP_INT_LINALG
     integer     :: i
     complex(SP) :: ctmp
     if (n_threads_now>1) then
       !$omp parallel do default(shared), private(i), reduction(+:ctmp)
       ctmp=cZERO
       do i=1,N
         ctmp=ctmp+conjg(CX(i))*CY(i)
       enddo 
       !$omp end parallel do
       Vstar_dot_V_c1_omp=ctmp
     else
       Vstar_dot_V_c1_omp=Vstar_dot_V(N,CX,CY)
     endif
#else
     Vstar_dot_V_c1_omp=Vstar_dot_V(N,CX,CY)
#endif
     !
   end function Vstar_dot_V_c1_omp
   !
   complex(SP) function Vstar_dot_V_c2_omp(N,CX,CY)
     integer,    intent(in) :: N
     complex(SP),intent(in) :: CX(:,:),CY(:,:)
     !
#if defined _OPENMP_INT_LINALG
     integer     :: i,j
     complex(SP) :: ctmp
     if (n_threads_now>1) then
       !$omp parallel do default(shared), private(i,j), reduction(+:ctmp), collapse(2)
       ctmp=cZERO
       do j=1,N/size(CX,1)
         do i=1,size(CX,1)
           ctmp=ctmp +conjg(CX(i,j))*CY(i,j)
         enddo 
       enddo 
       !$omp end parallel do
       Vstar_dot_V_c2_omp=ctmp
     else
       Vstar_dot_V_c2_omp=Vstar_dot_V(N,CX,CY)
     endif
#else
     Vstar_dot_V_c2_omp=Vstar_dot_V(N,CX,CY)
#endif
     !
   end function Vstar_dot_V_c2_omp
   !
   real(SP) function V_dot_V_r1_omp(N,CX,CY)
     integer, intent(in) :: N
     real(SP),intent(in) :: CX(:),CY(:)
     !
#if defined _OPENMP_INT_LINALG
     integer  :: i
     real(SP) :: rtmp
     if (n_threads_now>1) then
       !$omp parallel do default(shared), private(i), reduction(+:rtmp)
       rtmp=0.0_SP
       do i=1,N
         rtmp=rtmp +CX(i)*CY(i)
       enddo 
       !$omp end parallel do
       V_dot_V_r1_omp=rtmp
     else
       V_dot_V_r1_omp=V_dot_V(N,CX,CY)
     endif
#else
     V_dot_V_r1_omp=V_dot_V(N,CX,CY)
#endif
   end function V_dot_V_r1_omp
   !
   complex(SP) function V_dot_V_c1_omp(N,CX,CY)
     integer,    intent(in) :: N
     complex(SP),intent(in) :: CX(:),CY(:)
     !
#if defined _OPENMP_INT_LINALG
     integer     :: i
     complex(SP) :: ctmp
     if (n_threads_now>1) then
       !$omp parallel do default(shared), private(i), reduction(+:ctmp)
       ctmp=0.0_SP
       do i=1,N
         ctmp=ctmp +CX(i)*CY(i)
       enddo 
       !$omp end parallel do
       V_dot_V_c1_omp=ctmp
     else
       V_dot_V_c1_omp=V_dot_V(N,CX,CY)
     endif
#else
     V_dot_V_c1_omp=V_dot_V(N,CX,CY)
#endif
     !
   end function V_dot_V_c1_omp
   !
   complex(SP) function V_dot_V_c2_omp(N,CX,CY)
     integer,    intent(in) :: N
     complex(SP),intent(in) :: CX(:,:),CY(:,:)
     !
#if defined _OPENMP_INT_LINALG
     integer     :: i,j
     complex(SP) :: ctmp
     if (n_threads_now>1) then
       !$omp parallel do default(shared), private(i), reduction(+:ctmp), collapse(2)
       ctmp=0.0_SP
       do j=1,N/size(CX,1)
       do i=1,size(CX,1)
         ctmp=ctmp +CX(i,j)*CY(i,j)
       enddo 
       enddo 
       !$omp end parallel do
       V_dot_V_c2_omp=ctmp
     else
       V_dot_V_c2_omp=V_dot_V(N,CX,CY)
     endif
#else
     V_dot_V_c2_omp=V_dot_V(N,CX,CY)
#endif
     !
   end function V_dot_V_c2_omp
   !
end module

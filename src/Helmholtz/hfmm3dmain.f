c
      subroutine hfmm3dmain(nd,eps,zk,
     $     nsource,sourcesort,
     $     ifcharge,chargesort,
     $     ifdipole,dipstrsort,dipvecsort,
     $     ntarg,targsort,nexpc,expcsort,radssort,
     $     iaddr,rmlexp,lmptot,mptemp,mptemp2,lmptemp,
     $     itree,ltree,ipointer,isep,ndiv,nlevels, 
     $     nboxes,boxsize,mnbors,mnlist1,mnlist2,mnlist3,mnlist4,
     $     rscales,centers,laddr,nterms,ifpgh,pot,grad,hess,
     $     ifpghtarg,pottarg,gradtarg,hesstarg,
     $     ntj,jsort,scjsort)
      implicit none

      integer nd
      double precision eps
      integer nsource,ntarg, nexpc
      integer ndiv,nlevels

      integer ifcharge,ifdipole
      integer ifpgh,ifpghtarg

      double complex zk,zk2

      double precision sourcesort(3,nsource)

      double complex chargesort(nd,*)
      double complex dipstrsort(nd,*)
      double precision dipvecsort(nd,3,*)

      double precision targsort(3,ntarg)

      double complex pot(nd,*),grad(nd,3,*),hess(nd,6,*)
      double complex pottarg(nd,*),gradtarg(nd,3,*),hesstarg(nd,6,*)

      integer ntj
      double precision expcsort(3,nexpc)
      double complex jsort(nd,0:ntj,-ntj:ntj,nexpc)


      integer iaddr(2,nboxes), lmptot, lmptemp
      double precision rmlexp(lmptot)
      double precision mptemp(nd,lmptemp)
      double precision mptemp2(nd,lmptemp)
       
      double precision timeinfo(10)
      double precision centers(3,nboxes)
c
cc      tree variables
c
      integer isep, ltree
      integer laddr(2,0:nlevels)
      integer nterms(0:nlevels)
      integer ipointer(32)
      integer itree(ltree)
      integer nboxes
      double precision rscales(0:nlevels)
      double precision boxsize(0:nlevels)
c
cc      pw stuff
c
      integer nuall,ndall,nnall,nsall,neall,nwall
      integer nu1234,nd5678,nn1256,ns3478,ne1357,nw2468
      integer nn12,nn56,ns34,ns78,ne13,ne57,nw24,nw68
      integer ne1,ne3,ne5,ne7,nw2,nw4,nw6,nw8

      integer uall(200),dall(200),nall(120),sall(120),eall(72),wall(72)
      integer u1234(36),d5678(36),n1256(24),s3478(24)
      integer e1357(16),w2468(16),n12(20),n56(20),s34(20),s78(20)
      integer e13(20),e57(20),w24(20),w68(20)
      integer e1(20),e3(5),e5(5),e7(5),w2(5),w4(5),w6(5),w8(5)

      integer ntmax, nexpmax, nlams, nmax, nthmax, nphmax
      parameter (ntmax = 1000)
      double precision, allocatable :: carray(:,:), dc(:,:)
      double precision, allocatable :: rdplus(:,:,:)
      double precision, allocatable :: rdminus(:,:,:), rdsq3(:,:,:)
      double precision, allocatable :: rdmsq3(:,:,:)
      double complex, allocatable :: rdminus2(:,:,:),zeyep(:)
      double complex, allocatable :: rdplus2(:,:,:)
      double precision, allocatable :: zmone(:)
      integer nn,nnn
  
      double complex rlams(ntmax), whts(ntmax)

      double complex, allocatable :: rlsc(:,:,:)
      integer nfourier(ntmax), nphysical(ntmax)
      integer nexptot, nexptotp
      double complex, allocatable :: xshift(:,:),yshift(:,:),zshift(:,:)

      double complex fexp(100000), fexpback(100000)

      double complex, allocatable :: mexp(:,:,:,:)
      double complex, allocatable :: tmp(:,:,:)
      double complex, allocatable :: mexpf1(:,:),mexpf2(:,:)
      double complex, allocatable :: mexpp1(:,:),mexpp2(:,:),mexppall(:,:,:)

      double precision, allocatable :: rsc(:)
      double precision r1

      double precision scjsort(nexpc),radssort(nexpc)

c     temp variables
      integer i,j,k,l,ii,jj,kk,ll,idim
      integer ibox,jbox,ilev,npts
      integer nchild,nlist1,nlist2,nlist3,nlist4

      integer istart,iend,istartt,iendt,istarte,iende
      integer istarts,iends
      integer jstart,jend

      integer ifprint

      integer ifhesstarg
      double precision d,time1,time2,omp_get_wtime

      double precision sourcetmp(3)
      double complex chargetmp(nd)

      integer ix,iy,iz
      double precision rtmp
      double complex zmul

      integer nlege, lw7, lused7, itype
      double precision wlege(40000)

      double precision thresh

      integer mnbors,mnlist1, mnlist2,mnlist3,mnlist4
      double complex eye, ztmp,zmult
      double precision alphaj
      integer ctr,ifinit2
      double precision, allocatable :: xnodes(:),wts(:)
      double precision radius
      integer nquad2
      integer maX_nodes
      double precision pi
      
      integer istart0,istart1,istartm1,nprin
      double precision rtmp1,rtmp2,rtmp3,rtmp4
      double complex ima
      data ima/(0.0d0,1.0d0)/

      integer nlfbox


      pi = 4.0d0*atan(1.0d0)

      nmax = 0
      do i=0,nlevels
         if(nmax.lt.nterms(i)) nmax = nterms(i)
      enddo

      allocate(rsc(0:nmax))

c
cc     threshold for computing interactions,
c      interactions will be ignored
c      for all pairs of sources and targets
c      which satisfy |zk*r| < thresh
c      where r is the disance between them

      thresh = 1.0d-16*abs(zk)*boxsize(0)


      allocate(zeyep(-nmax:nmax),zmone(0:2*nmax))
      
      zeyep(0) = 1
      zmult = -ima
      do i=1,nmax
         zeyep(i) = zeyep(i-1)*zmult
         zeyep(-i) = zeyep(-i+1)/zmult
      enddo


      zmone(0) = 1
      do i=1,2*nmax
         zmone(i) = -zmone(i-1)
      enddo

c     ifprint is an internal information printing flag. 
c     Suppressed if ifprint=0.
c     Prints timing breakdown and other things if ifprint=1.
c     Prints timing breakdown, list information, and other things if ifprint=2.
c       
        ifprint=1
c
c
c     ... set the expansion coefficients to zero
c
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,j,k,idim)
      do i=1,nexpc
         do k=-ntj,ntj
           do j = 0,ntj
              do idim=1,nd
                jsort(idim,j,k,i)=0
              enddo
           enddo
         enddo
      enddo
C$OMP END PARALLEL DO

c       
        do i=1,10
          timeinfo(i)=0
        enddo

c
c       ... set all multipole and local expansions to zero
c
      do ilev = 0,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox)
         do ibox = laddr(1,ilev),laddr(2,ilev)
            call mpzero(nd,rmlexp(iaddr(1,ibox)),nterms(ilev))
            call mpzero(nd,rmlexp(iaddr(2,ibox)),nterms(ilev))
         enddo
C$OMP END PARALLEL DO          
       enddo


c
ccc       set scjsort
c
      do ilev=0,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nchild,istart,iend,i)
         do ibox=laddr(1,ilev),laddr(2,ilev)
            nchild = itree(ipointer(3)+ibox-1)
            if(nchild.gt.0) then
               istart = itree(ipointer(16)+ibox-1)
               iend = itree(ipointer(17)+ibox-1)
               do i=istart,iend
                  scjsort(i) = rscales(ilev)
                  radssort(i) = min(radssort(i),boxsize(ilev)/32*
     1                            sqrt(3.0d0))
               enddo
            endif
         enddo
C$OMP END PARALLEL DO
      enddo


c    initialize legendre function evaluation routines
      nlege = 100
      lw7 = 40000
      call ylgndrfwini(nlege,wlege,lw7,lused7)

c
c
      if(ifprint .ge. 1) 
     $   call prinf('=== STEP 1 (form mp) ====*',i,0)
        time1=second()
C$        time1=omp_get_wtime()
c
c       ... step 1, locate all charges, assign them to boxes, and
c       form multipole expansions



      do ilev=2,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,npts,istart,iend,nchild)
C
         if(ifcharge.eq.1.and.ifdipole.eq.0) then
            do ibox=laddr(1,ilev),laddr(2,ilev)

               istart = itree(ipointer(10)+ibox-1)
               iend = itree(ipointer(11)+ibox-1)
               npts = iend-istart+1

               nchild = itree(ipointer(3)+ibox-1)

               if(npts.gt.0.and.nchild.eq.0) then
                  call h3dformmpc(nd,zk,rscales(ilev),
     1            sourcesort(1,istart),chargesort(1,istart),npts,
     2            centers(1,ibox),nterms(ilev),
     3            rmlexp(iaddr(1,ibox)),wlege,nlege)          
               endif
            enddo
         endif
         if(ifdipole.eq.1.and.ifcharge.eq.1) then
            do ibox=laddr(1,ilev),laddr(2,ilev)

               istart = itree(ipointer(10)+ibox-1)
               iend = itree(ipointer(11)+ibox-1)
               npts = iend-istart+1

               nchild = itree(ipointer(3)+ibox-1)

               if(npts.gt.0.and.nchild.eq.0) then
                  call h3dformmpcd(nd,zk,rscales(ilev),
     1            sourcesort(1,istart),chargesort(1,istart),
     2            dipstrsort(1,istart),dipvecsort(1,1,istart),npts,
     2            centers(1,ibox),nterms(ilev),
     3            rmlexp(iaddr(1,ibox)),wlege,nlege)          
               endif
            enddo
         endif
C$OMP END PARALLEL DO          
      enddo

      time2=second()
C$    time2=omp_get_wtime()
      timeinfo(1)=time2-time1

      if(ifprint.ge.1)
     $   call prinf('=== STEP 2 (form lo) ===*',i,0)
      time1=second()
C$    time1=omp_get_wtime()


      if(ifcharge.eq.1.and.ifdipole.eq.0) then
      do ilev=2,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,jbox,nlist4,istart,iend,npts,i)
C$OMP$SCHEDULE(DYNAMIC)
         do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist4 = itree(ipointer(26)+ibox-1)
            do i=1,nlist4
               jbox = itree(ipointer(27)+(ibox-1)*mnlist4+i-1)

c              Form local expansion for all boxes in list3
c              of the current box


               istart = itree(ipointer(10)+jbox-1)
               iend = itree(ipointer(11)+jbox-1)
               npts = iend-istart+1
               if(npts.gt.0) then
                  call h3dformtac(nd,zk,rscales(ilev),
     1             sourcesort(1,istart),chargesort(1,istart),npts,
     2             centers(1,ibox),nterms(ilev),
     3             rmlexp(iaddr(2,ibox)),wlege,nlege)
               endif
            enddo
         enddo
C$OMP END PARALLEL DO
      enddo
      endif


      if(ifcharge.eq.1.and.ifdipole.eq.1) then
      do ilev=2,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,jbox,nlist4,istart,iend,npts,i)
C$OMP$SCHEDULE(DYNAMIC)
         do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist4 = itree(ipointer(26)+ibox-1)
            do i=1,nlist4
               jbox = itree(ipointer(27)+(ibox-1)*mnlist4+i-1)

c              Form local expansion for all boxes in list3
c              of the current box


               istart = itree(ipointer(10)+jbox-1)
               iend = itree(ipointer(11)+jbox-1)
               npts = iend-istart+1
               if(npts.gt.0) then
                   call h3dformtacd(nd,zk,rscales(ilev),
     1              sourcesort(1,istart),chargesort(1,istart),
     2              dipstrsort(1,istart),
     3              dipvecsort(1,1,istart),npts,centers(1,ibox),
     4              nterms(ilev),rmlexp(iaddr(2,ibox)),wlege,nlege)
               endif
            enddo
         enddo
C$OMP END PARALLEL DO         
      enddo

      endif
      time2=second()
C$    time2=omp_get_wtime()
      timeinfo(2)=time2-time1

c       
      if(ifprint .ge. 1)
     $      call prinf('=== STEP 3 (merge mp) ====*',i,0)
      time1=second()
C$    time1=omp_get_wtime()
c

      max_nodes = 10000
      allocate(xnodes(max_nodes))
      allocate(wts(max_nodes))

      do ilev=nlevels-1,0,-1
         nquad2 = nterms(ilev)*2.5
         nquad2 = max(6,nquad2)
         ifinit2 = 1
         call legewhts(nquad2,xnodes,wts,ifinit2)
         radius = boxsize(ilev)/2*sqrt(3.0d0)

C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,i,jbox,istart,iend,npts)
         do ibox = laddr(1,ilev),laddr(2,ilev)
            do i=1,8
               jbox = itree(ipointer(4)+8*(ibox-1)+i-1)
               if(jbox.gt.0) then
                  istart = itree(ipointer(10)+jbox-1)
                  iend = itree(ipointer(11)+jbox-1)
                  npts = iend-istart+1

                  if(npts.gt.0) then
                     call h3dmpmp(nd,zk,rscales(ilev+1),
     1               centers(1,jbox),rmlexp(iaddr(1,jbox)),
     2               nterms(ilev+1),rscales(ilev),centers(1,ibox),
     3               rmlexp(iaddr(1,ibox)),nterms(ilev),
     4               radius,xnodes,wts,nquad2)
                  endif
               endif
            enddo
         enddo
C$OMP END PARALLEL DO          
      enddo

      time2=second()
C$    time2=omp_get_wtime()
      timeinfo(3)=time2-time1


      nd = 1

      if(ifprint.ge.1)
     $    call prinf('=== Step 4 (mp to loc) ===*',i,0)
c      ... step 3, convert multipole expansions into local
c       expansions

      time1 = second()
C$        time1=omp_get_wtime()
      do ilev = 2,nlevels

c
cc       load the necessary quadrature for plane waves
c
      
         zk2 = zk*boxsize(ilev)
         if(real(zk2).le.pi.and.imag(zk2).le.0.02d0) then
            call lreadall(eps,zk2,nlams,rlams,whts,nfourier,
     1           nphysical,ntmax,ier)


            nphmax = 0
            nthmax = 0
            nexptotp = 0
            nexptot = 0
            do i=1,nlams
               nexptotp = nexptotp + nphysical(i)
               nexptot = nexptot + 2*nfourier(i)+1
               if(nfourier(i).gt.nthmax) nthmax = nfourier(i)
               if(nphysical(i).gt.nphmax) nphmax = nphysical(i)
            enddo

            allocate(xshift(-5:5,nexptotp))
            allocate(yshift(-5:5,nexptotp))
            allocate(zshift(5,nexptotp))
            allocate(rlsc(0:nterms(ilev),0:nterms(ilev),nlams))
            allocate(tmp(0:nterms(ilev),-nterms(ilev):nterms(ilev)))
 
            allocate(mexpf1(nexptot),mexpf2(nexptot),mexpp1(nexptotp))
            allocate(mexpp2(nexptotp),mexppall(nexptotp,16))


c
cc      NOTE: there can be some memory savings here
c
            allocate(mexp(nexptotp,nboxes,6))

            nn = nterms(ilev)
            allocate(carray(4*nn+1,4*nn+1))
            allocate(dc(0:4*nn,0:4*nn))
            allocate(rdplus(0:nn,0:nn,-nn:nn))
            allocate(rdminus(0:nn,0:nn,-nn:nn))
            allocate(rdsq3(0:nn,0:nn,-nn:nn))
            allocate(rdmsq3(0:nn,0:nn,-nn:nn))

c     generate rotation matrices and carray
            call rotgen(nn,carray,rdplus,rdminus,rdsq3,rdmsq3,dc)


            call rlscini(rlsc,nlams,rlams,zk2,nterms(ilev))
            call mkexps(rlams,nlams,nphysical,nexptotp,zk2,xshift,
     1           yshift,zshift)
            call mkfexp(nlams,nfourier,nphysical,fexp,fexpback)
c
cc      zero out mexp
c
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(idim,i,j,k)
            do k=1,6
               do i=1,nboxes
                  do j=1,nexptotp
                     do idim=1,nd
                        mexp(idim,j,i,k) = 0.0d0
                     enddo
                  enddo
               enddo
            enddo
C$OMP END PARALLEL DO        


c
cc         compute powers of scaling parameter
c          for rescaling the multipole expansions
c
          
           r1 = rscales(ilev)
           rsc(0) = 0
           do i=1,nterms(ilev)
             rsc(i) = rsc(i-1)*r1
           enddo

c
cc         create multipole to plane wave expansion for
c          all boxes at this level
c
C$OMP PARALLEL DO DEFAULT (SHARED)
C$OMP$PRIVATE(ibox,istart,iend,npts,tmp,mexpf1,mexpf2,mptemp,ctr)
C$OMP$PRIVATE(ii,jj)
            do ibox = laddr(1,ilev),laddr(2,ilev)
               istart = itree(ipointer(10)+ibox-1)
               iend = itree(ipointer(11)+ibox-1)
               npts = iend - istart+1
               if(npts.gt.0) then

c           rescale multipole expansion
                  call mpscale(nd,nterms,rmlexp(iaddr(1,ibox)),rsc,tmp)

                  call mpoletoexp(nd,tmp,nterms(ilev),
     1                  nlams,nfourier,nexptot,mexpf1,mexpf2,rlsc) 

                  call ftophys(nd,mexpf1,nlams,nfourier,nphysical,
     1                 mexp(1,ibox,1),fexp)           

                  call ftophys(nd,mexpf2,nlams,nfourier,nphysical,
     1                 mexp(1,ibox,2),fexp)


c             form mexpnorth, mexpsouth for current box

c             Rotate mpole for computing mexpnorth and
c             mexpsouth
                  call rotztoy(nd,nterms(ilev),tmp,
     1                           mptemp,rdminus)

                  call mpoletoexp(nd,mptemp,nterms(ilev),nlams,
     1                  nfourier,nexptot,mexpf1,mexpf2,rlsc)

                  call ftophys(nd,mexpf1,nlams,nfourier,
     1                 nphysical,mexp(1,ibox,3),fexp)           

                  call ftophys(nd,mexpf2,nlams,nfourier,
     1                 nphysical,mexp(1,ibox,4),fexp)   


c             Rotate mpole for computing mexpeast, mexpwest
                  call rotztox(nd,nterms(ilev),tmp,
     1                              mptemp,rdplus)
                  call mpoletoexp(nd,mptemp,nterms(ilev),nlams,
     1                  nfourier,nexptot,mexpf1,mexpf2,rlsc)

                  call ftophys(nd,mexpf1,nlams,nfourier,
     1                 nphysical,mexp(1,ibox,5),fexp)

                  call ftophys(nd,mexpf2,nlams,nfourier,
     1                 nphysical,mexp(1,ibox,6),fexp)           

               endif
            enddo
C$OMP END PARALLEL DO         


c
cc         loop over parent boxes and ship plane wave
c          expansions to the first child of parent 
c          boxes. 
c          The codes are now written from a gathering perspective
c
c          so the first child of the parent is the one
c          recieving all the local expansions
c          coming from all the lists
c
c          
c

C$OMP PARALLEL DO DEFAULT (SHARED)
C$OMP$PRIVATE(ibox,istart,iend,npts,nchild)
C$OMP$PRIVATE(mexpf1,mexpf2,mexpp1,mexpp2,mexppall)
C$OMP$PRIVATE(nuall,uall,ndall,dall,nnall,nall,nsall,sall)
C$OMP$PRIVATE(neall,eall,nwall,wall,nu1234,u1234,nd5678,d5678)
C$OMP$PRIVATE(nn1256,n1256,ns3478,s3478,ne1357,e1357,nw2468,w2468)
C$OMP$PRIVATE(nn12,n12,nn56,n56,ns34,s34,ns78,s78,ne13,e13,ne57,e57)
C$OMP$PRIVATE(nw24,w24,nw68,w68,ne1,e1,ne3,e3,ne5,e5,ne7,e7)
C$OMP$PRIVATE(nw2,w2,nw4,w4,nw6,w6,nw8,w8)
            do ibox = laddr(1,ilev-1),laddr(2,ilev-1)
           
               npts = 0

               if(ifpghtarg.gt.0) then
                  istart = itree(ipointer(12)+ibox-1)
                  iend = itree(ipointer(13)+ibox-1)
                  npts = npts + iend-istart+1
               endif

               istart = itree(ipointer(14)+ibox-1)
               iend = itree(ipointer(17)+ibox-1)
               npts = npts + iend-istart+1

               nchild = itree(ipointer(3)+ibox-1)

               if(ifpgh.gt.0) then
                  istart = itree(ipointer(10)+ibox-1)
                  iend = itree(ipointer(11)+ibox-1)
                  npts = npts + iend-istart+1
               endif


               if(npts.gt.0.and.nchild.gt.0) then

              
                  call getpwlistall(ibox,boxsize(ilev),nboxes,
     1            itree(ipointer(18)+ibox-1),itree(ipointer(19)+
     2            mnbors*(ibox-1)),nchild,itree(ipointer(4)),centers,
     3            isep,nuall,uall,ndall,dall,nnall,nall,nsall,sall,
     4            neall,eall,nwall,wall,nu1234,u1234,nd5678,d5678,
     5            nn1256,n1256,ns3478,s3478,ne1357,e1357,nw2468,w2468,
     6            nn12,n12,nn56,n56,ns34,s34,ns78,s78,ne13,e13,ne57,
     7            e57,nw24,w24,nw68,w68,ne1,e1,ne3,e3,ne5,e5,ne7,e7,
     8            nw2,w2,nw4,w4,nw6,w6,nw8,w8)


                  call processudexp(nd,zk2,ibox,ilev,nboxes,centers,
     1            itree(ipointer(4)),rscales(ilev),nterms(ilev),
     2            iaddr,rmlexp,rlams,whts,
     3            nlams,nfourier,nphysical,nthmax,nexptot,nexptotp,mexp,
     4            nuall,uall,nu1234,u1234,ndall,dall,nd5678,d5678,
     5            mexpf1,mexpf2,mexpp1,mexpp2,mexppall(1,1),
     6            mexppall(1,2),mexppall(1,3),mexppall(1,4),xshift,
     7            yshift,zshift,fexpback,rlsc)


                  call processnsexp(nd,zk2,ibox,ilev,nboxes,centers,
     1            itree(ipointer(4)),rscales(ilev),nterms(ilev),
     2            iaddr,rmlexp,rlams,whts,
     3            nlams,nfourier,nphysical,nthmax,nexptot,nexptotp,mexp,
     4            nnall,nall,nn1256,n1256,nn12,n12,nn56,n56,nsall,sall,
     5            ns3478,s3478,ns34,s34,ns78,s78,
     6            mexpf1,mexpf2,mexpp1,mexpp2,mexppall(1,1),
     7            mexppall(1,2),mexppall(1,3),mexppall(1,4),
     8            mexppall(1,5),mexppall(1,6),mexppall(1,7),
     9            mexppall(1,8),rdplus,xshift,yshift,zshift,
     9            fexpback,rlsc)

                  call processewexp(nd,zk2,ibox,ilev,nboxes,centers,
     1            itree(ipointer(4)),rscales(ilev),nterms(ilev),
     2            iaddr,rmlexp,rlams,whts,
     3            nlams,nfourier,nphysical,nthmax,nexptot,nexptotp,mexp,
     4            neall,eall,ne1357,e1357,ne13,e13,ne57,e57,ne1,e1,
     5            ne3,e3,ne5,e5,ne7,e7,nwall,wall,
     5            nw2468,w2468,nw24,w24,nw68,w68,
     5            nw2,w2,nw4,w4,nw6,w6,nw8,w8,
     6            mexpf1,mexpf2,mexpp1,mexpp2,mexppall(1,1),
     7            mexppall(1,2),mexppall(1,3),mexppall(1,4),
     8            mexppall(1,5),mexppall(1,6),
     8            mexppall(1,7),mexppall(1,8),mexppall(1,9),
     9            mexppall(1,10),mexppall(1,11),mexppall(1,12),
     9            mexppall(1,13),mexppall(1,14),mexppall(1,15),
     9            mexppall(1,16),rdminus,xshift,yshift,zshift,
     9            fexpback,rlsc)
               endif
            enddo
C$OMP END PARALLEL DO        

            deallocate(xshift,yshift,zshift,rlsc,tmp)
            deallocate(carray,dc,rdplus,rdminus,rdsq3,rdmsq3)

            deallocate(mexpf1,mexpf2,mexpp1,mexpp2,mexppall,mexp)

         endif

         if(real(zk2).ge.pi.or.imag(zk2).ge.0.02d0) then

            nquad2 = nterms(ilev)*1.2
            nquad2 = max(6,nquad2)
            ifinit2 = 1
            ier = 0

            call legewhts(nquad2,xnodes,wts,ifinit2)

            radius = boxsize(ilev)/2*sqrt(3.0d0)
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,istart,iend,npts,nlist2,i,jbox)
            do ibox = laddr(1,ilev),laddr(2,ilev)

               npts = 0
               if(ifpghtarg.gt.0) then
                  istart = itree(ipointer(12)+ibox-1)
                  iend = itree(ipointer(13)+ibox-1)
                  npts = npts + iend - istart + 1
               endif

               istart = itree(ipointer(14)+ibox-1)
               iend = itree(ipointer(17)+ibox-1)
               npts = npts + iend-istart+1

               if(ifpgh.gt.0) then
                  istart = itree(ipointer(10)+ibox-1)
                  iend = itree(ipointer(11)+ibox-1)
                  npts = npts + iend-istart+1
               endif


               nlist2 = itree(ipointer(22)+ibox-1)
               if(npts.gt.0) then
                  do i =1,nlist2
                     jbox = itree(ipointer(23)+mnlist2*(ibox-1)+i-1)

                     istart = itree(ipointer(10)+jbox-1)
                     iend = itree(ipointer(11)+jbox-1)
                     npts = iend-istart+1

                     if(npts.gt.0) then
                        call h3dmploc(nd,zk,rscales(ilev),
     1                  centers(1,jbox),
     1                  rmlexp(iaddr(1,jbox)),nterms(ilev),
     2                  rscales(ilev),centers(1,ibox),
     2                  rmlexp(iaddr(2,ibox)),nterms(ilev),
     3                  radius,xnodes,wts,nquad2)
                     endif
                  enddo
               endif
           enddo
C$OMP END PARALLEL DO        
         endif
      enddo
      time2 = second()
C$        time2=omp_get_wtime()
      timeinfo(4) = time2-time1


      if(ifprint.ge.1)
     $    call prinf('=== Step 5 (split loc) ===*',i,0)

      time1 = second()
C$        time1=omp_get_wtime()
      do ilev = 2,nlevels-1

        nquad2 = nterms(ilev)*2
        nquad2 = max(6,nquad2)
        ifinit2 = 1
        call legewhts(nquad2,xnodes,wts,ifinit2)
        radius = boxsize(ilev+1)/2*sqrt(3.0d0)

C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,i,jbox,istart,iend,npts)
         do ibox = laddr(1,ilev),laddr(2,ilev)

            npts = 0

            if(ifpghtarg.gt.0) then
               istart = itree(ipointer(12)+ibox-1)
               iend = itree(ipointer(13)+ibox-1)
               npts = npts + iend-istart+1
            endif

            istart = itree(ipointer(14)+ibox-1)
            iend = itree(ipointer(17)+ibox-1)
            npts = npts + iend-istart+1

            if(ifpgh.gt.0) then
               istart = itree(ipointer(10)+ibox-1)
               iend = itree(ipointer(11)+ibox-1)
               npts = npts + iend-istart+1
            endif

            if(npts.gt.0) then
               do i=1,8
                  jbox = itree(ipointer(4)+8*(ibox-1)+i-1)
                  if(jbox.gt.0) then
                     call h3dlocloc(nd,zk,rscales(ilev),
     1                centers(1,ibox),rmlexp(iaddr(2,ibox)),
     2                nterms(ilev),rscales(ilev+1),centers(1,jbox),
     3                rmlexp(iaddr(2,jbox)),nterms(ilev+1),
     4                radius,xnodes,wts,nquad2)
                  endif
               enddo
            endif
         enddo
C$OMP END PARALLEL DO         
      enddo
      time2 = second()
C$        time2=omp_get_wtime()
      timeinfo(5) = time2-time1


      if(ifprint.ge.1)
     $    call prinf('=== step 6 (mp eval) ===*',i,0)
      time1 = second()
C$        time1=omp_get_wtime()

c
cc       shift mutlipole expansions to expansion center
c        (Note: this part is not relevant for particle codes.
c         It is relevant only for QBX codes)


      nquad2 = 2*ntj
      call legewhts(nquad2,xnodes,wts,ifinit2)
      do ilev=1,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nlist3,istart,iend,npts,j,i,jbox)
C$OMP$PRIVATE(mptemp)
C$OMP$SCHEDULE(DYNAMIC)
         do ibox = laddr(1,ilev),laddr(2,ilev)
            nlist3 = itree(ipointer(24)+ibox-1)

            istart = itree(ipointer(16)+ibox-1)
            iend = itree(ipointer(17)+ibox-1)

            do j=istart,iend
               do i=1,nlist3
                  jbox = itree(ipointer(25)+(ibox-1)*mnlist3+i-1)
c
cc                  shift multipole expansion directly from box
c                   center to expansion center
                     call h3dmploc(nd,zk,rscales(ilev+1),
     1               centers(1,jbox),
     1               rmlexp(iaddr(1,jbox)),nterms(ilev+1),
     2               scjsort(j),expcsort(1,j),
     2               jsort(1,0,-ntj,j),ntj,
     3               radssort(j),xnodes,wts,nquad2)
               enddo
            enddo
         enddo
C$OMP END PARALLEL DO  
      enddo

c
cc       evaluate multipole expansions at source locations
c

      do ilev=1,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nlist3,istart,iend,npts,j,i,jbox)
C$OMP$SCHEDULE(DYNAMIC)
        if(ifpgh.eq.1) then         
          do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist3 = itree(ipointer(24)+ibox-1)
            istart = itree(ipointer(10)+ibox-1)
            iend = itree(ipointer(11)+ibox-1)

            npts = iend-istart+1

            do i=1,nlist3
              jbox = itree(ipointer(25)+(ibox-1)*mnlist3+i-1)
              call h3dmpevalp(nd,zk,rscales(ilev+1),centers(1,jbox),
     1          rmlexp(iaddr(1,jbox)),nterms(ilev+1),
     2          sourcesort(1,istart),npts,pot(1,istart),wlege,nlege,
     3          thresh)
            enddo
          enddo
        endif

        if(ifpgh.eq.2) then
          do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist3 = itree(ipointer(24)+ibox-1)
            istart = itree(ipointer(10)+ibox-1)
            iend = itree(ipointer(11)+ibox-1)

            npts = iend-istart+1

            do i=1,nlist3
              jbox = itree(ipointer(25)+(ibox-1)*mnlist3+i-1)
              call h3dmpevalg(nd,zk,rscales(ilev+1),centers(1,jbox),
     1          rmlexp(iaddr(1,jbox)),nterms(ilev+1),
     2          sourcesort(1,istart),npts,pot(1,istart),
     3          grad(1,1,istart),wlege,nlege,thresh)
            enddo
          enddo
        endif

        if(ifpghtarg.eq.1) then         
          do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist3 = itree(ipointer(24)+ibox-1)
            istart = itree(ipointer(12)+ibox-1)
            iend = itree(ipointer(13)+ibox-1)

            npts = iend-istart+1

            do i=1,nlist3
              jbox = itree(ipointer(25)+(ibox-1)*mnlist3+i-1)
              call h3dmpevalp(nd,zk,rscales(ilev+1),centers(1,jbox),
     1          rmlexp(iaddr(1,jbox)),nterms(ilev+1),
     2          targsort(1,istart),npts,pottarg(1,istart),wlege,nlege,
     3          thresh)
            enddo
          enddo
        endif

        if(ifpghtarg.eq.2) then
          do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist3 = itree(ipointer(24)+ibox-1)
            istart = itree(ipointer(12)+ibox-1)
            iend = itree(ipointer(13)+ibox-1)

            npts = iend-istart+1

            do i=1,nlist3
              jbox = itree(ipointer(25)+(ibox-1)*mnlist3+i-1)
              call h3dmpevalg(nd,zk,rscales(ilev+1),centers(1,jbox),
     1          rmlexp(iaddr(1,jbox)),nterms(ilev+1),
     2          targsort(1,istart),npts,pottarg(1,istart),
     3          gradtarg(1,1,istart),wlege,nlege,thresh)
            enddo
          enddo
        endif
C$OMP END PARALLEL DO
      enddo

      time2 = second()
C$        time2=omp_get_wtime()
      timeinfo(6) = time2-time1

      if(ifprint.ge.1)
     $    call prinf('=== step 7 (eval lo) ===*',i,0)

c     ... step 7, evaluate all local expansions
c

      nquad2 = 2*ntj
      call legewhts(nquad2,xnodes,wts,ifinit2)
      time1 = second()
C$        time1=omp_get_wtime()
C

c
cc       shift local expansion to local epxanion at expansion centers
c        (note: this part is not relevant for particle codes.
c        it is relevant only for qbx codes)

      do ilev = 0,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nchild,istart,iend,i)
C$OMP$SCHEDULE(DYNAMIC)      
         do ibox = laddr(1,ilev),laddr(2,ilev)
            nchild=itree(ipointer(3)+ibox-1)
            if(nchild.eq.0) then 
               istart = itree(ipointer(16)+ibox-1)
               iend = itree(ipointer(17)+ibox-1)
               do i=istart,iend

                  call h3dlocloc(nd,zk,rscales(ilev),
     1             centers(1,ibox),rmlexp(iaddr(2,ibox)),
     2             nterms(ilev),rscales(ilev),expcsort(1,i),
     3             jsort(1,0,-ntj,i),ntj,radssort(i),xnodes,wts,
     4             nquad2)
               enddo
            endif
         enddo
C$OMP END PARALLEL DO
      enddo

c
cc        evaluate local expansion at source and target
c         locations
c
      do ilev = 0,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nchild,istart,iend,i)
C$OMP$SCHEDULE(DYNAMIC)      
        if(ifpgh.eq.1) then
          do ibox = laddr(1,ilev),laddr(2,ilev)
            nchild=itree(ipointer(3)+ibox-1)
            if(nchild.eq.0) then 
              istart = itree(ipointer(10)+ibox-1)
              iend = itree(ipointer(11)+ibox-1)
              npts = iend-istart+1
              call h3dtaevalp(nd,zk,rscales(ilev),centers(1,ibox),
     1         rmlexp(iaddr(2,ibox)),nterms(ilev),sourcesort(1,istart),
     2         npts,pot(1,istart),wlege,nlege)
            endif
          enddo
        endif

        if(ifpgh.eq.2) then
          do ibox = laddr(1,ilev),laddr(2,ilev)
            nchild=itree(ipointer(3)+ibox-1)
            if(nchild.eq.0) then 
              istart = itree(ipointer(10)+ibox-1)
              iend = itree(ipointer(11)+ibox-1)
              npts = iend-istart+1
              call h3dtaevalg(nd,zk,rscales(ilev),centers(1,ibox),
     1         rmlexp(iaddr(2,ibox)),nterms(ilev),sourcesort(1,istart),
     2         npts,pot(1,istart),grad(1,1,istart),wlege,nlege)
            endif
          enddo
        endif

        if(ifpghtarg.eq.1) then
          do ibox = laddr(1,ilev),laddr(2,ilev)
            nchild=itree(ipointer(3)+ibox-1)
            if(nchild.eq.0) then 
              istart = itree(ipointer(12)+ibox-1)
              iend = itree(ipointer(13)+ibox-1)
              npts = iend-istart+1
              call h3dtaevalp(nd,zk,rscales(ilev),centers(1,ibox),
     1         rmlexp(iaddr(2,ibox)),nterms(ilev),targsort(1,istart),
     2         npts,pottarg(1,istart),wlege,nlege)
            endif
          enddo
        endif

        if(ifpghtarg.eq.2) then
          do ibox = laddr(1,ilev),laddr(2,ilev)
            nchild=itree(ipointer(3)+ibox-1)
            if(nchild.eq.0) then 
              istart = itree(ipointer(12)+ibox-1)
              iend = itree(ipointer(13)+ibox-1)
              npts = iend-istart+1
              call h3dtaevalg(nd,zk,rscales(ilev),centers(1,ibox),
     1         rmlexp(iaddr(2,ibox)),nterms(ilev),targsort(1,istart),
     2         npts,pottarg(1,istart),gradtarg(1,1,istart),wlege,nlege)
            endif
          enddo
        endif
C$OMP END PARALLEL DO         
      enddo
    
      time2 = second()
C$        time2=omp_get_wtime()
      timeinfo(7) = time2 - time1

      if(ifprint .ge. 1)
     $     call prinf('=== STEP 8 (direct) =====*',i,0)
      time1=second()
C$        time1=omp_get_wtime()

c
cc       directly form local expansions for list1 sources
c        at expansion centers. 
c        (note: this part is not relevant for particle codes.
c         It is relevant only for qbx codes)


      do ilev=0,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istarte,iende,nlist1,i,jbox)
C$OMP$PRIVATE(jstart,jend)
         do ibox = laddr(1,ilev),laddr(2,ilev)
            istarte = itree(ipointer(16)+ibox-1)
            iende = itree(ipointer(17)+ibox-1)

            nlist1 = itree(ipointer(20)+ibox-1)
   
            do i =1,nlist1
               jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)


               jstart = itree(ipointer(10)+jbox-1)
               jend = itree(ipointer(11)+jbox-1)

               call hfmm3dexpc_direct(nd,zk,jstart,jend,istarte,
     1         iende,sourcesort,ifcharge,chargesort,ifdipole,
     2         dipstrsort,dipvecsort,expcsort,jsort,scjsort,ntj,
     3         wlege,nlege)
            enddo
         enddo
C$OMP END PARALLEL DO
      enddo

c
cc        directly evaluate potential at sources and targets 
c         due to sources in list1

      do ilev=0,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istarts,iends,istartt,iendt,nlist1,i,jbox)
C$OMP$PRIVATE(jstart,jend,npts0,npts1,npts2)
c
cc           evaluate at the sources
c

        if(ifpgh.eq.1) then
          if(ifcharge.eq.1.and.ifdipole.eq.0) then
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istarts = itree(ipointer(10)+ibox-1)
              iends = itree(ipointer(11)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)

              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call h3ddirectcp(nd,zk,sourcesort(jstart),
     1             chargesort(1,jstart),npts,sourcesort(1,istarts),
     2             npts0,pot(1,istarts),thresh)          
              enddo
            enddo
          endif

          if(ifcharge.eq.1.and.ifdipole.eq.1) then
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istarts = itree(ipointer(10)+ibox-1)
              iends = itree(ipointer(11)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call h3ddirectcdp(nd,zk,sourcesort(jstart),
     1             chargesort(1,jstart),dipstrsort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,sourcesort(1,istarts),
     2             npts0,pot(1,istarts),thresh)          
              enddo
            enddo
          endif
        endif

        if(ifpgh.eq.2) then
          if(ifcharge.eq.1.and.ifdipole.eq.0) then
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istarts = itree(ipointer(10)+ibox-1)
              iends = itree(ipointer(11)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)

              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call h3ddirectcg(nd,zk,sourcesort(jstart),
     1             chargesort(1,jstart),npts,sourcesort(1,istarts),
     2             npts0,pot(1,istarts),grad(1,1,istarts),thresh)   
              enddo
            enddo
          endif

          if(ifcharge.eq.1.and.ifdipole.eq.1) then
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istarts = itree(ipointer(10)+ibox-1)
              iends = itree(ipointer(11)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call h3ddirectcdg(nd,zk,sourcesort(jstart),
     1             chargesort(1,jstart),dipstrsort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,sourcesort(1,istarts),
     2             npts0,pot(1,istarts),grad(1,1,istarts),thresh)          
              enddo
            enddo
          endif
        endif

        if(ifpghtarg.eq.1) then
          if(ifcharge.eq.1.and.ifdipole.eq.0) then
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istartt = itree(ipointer(12)+ibox-1)
              iendt = itree(ipointer(13)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)

              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call h3ddirectcp(nd,zk,sourcesort(jstart),
     1             chargesort(1,jstart),npts,targsort(1,istartt),
     2             npts0,pottarg(1,istartt),thresh)          
              enddo
            enddo
          endif

          if(ifcharge.eq.1.and.ifdipole.eq.1) then
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istartt = itree(ipointer(12)+ibox-1)
              iendt = itree(ipointer(13)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call h3ddirectcdp(nd,zk,sourcesort(jstart),
     1             chargesort(1,jstart),dipstrsort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,targsort(1,istartt),
     2             npts0,pottarg(1,istartt),thresh)          
              enddo
            enddo
          endif
        endif

        if(ifpgh.eq.2) then
          if(ifcharge.eq.1.and.ifdipole.eq.0) then
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istartt = itree(ipointer(12)+ibox-1)
              iendt = itree(ipointer(13)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)

              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call h3ddirectcg(nd,zk,sourcesort(jstart),
     1             chargesort(1,jstart),npts,targsort(1,istartt),
     2             npts0,pot(1,istartt),grad(1,1,istartt),thresh)   
              enddo
            enddo
          endif

          if(ifcharge.eq.1.and.ifdipole.eq.1) then
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istartt = itree(ipointer(12)+ibox-1)
              iendt = itree(ipointer(13)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call h3ddirectcdg(nd,zk,sourcesort(jstart),
     1             chargesort(1,jstart),dipstrsort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,targsort(1,istartt),
     2             npts0,pot(1,istartt),grad(1,1,istartt),thresh)          
              enddo
            enddo
          endif
        endif
C$OMP END PARALLEL DO     
      enddo
 
      time2 = second()
C$        time2=omp_get_wtime()
      timeinfo(8) = time2-time1
      if(ifprint.ge.1) call prin2('timeinfo=*',timeinfo,6)
      d = 0
      do i = 1,8
         d = d + timeinfo(i)
      enddo

      if(ifprint.ge.1) call prin2('sum(timeinfo)=*',d,1)

      return
      end


c------------------------------------------------------------------
      subroutine hfmm3dexpc_direct(nd,zk,istart,iend,jstart,
     $     jend,source,ifcharge,charge,ifdipole,dipstr,
     $     dipvec,targ,texps,scj,ntj,wlege,nlege)
c---------------------------------------------------------------
c     This subroutine adds the local expansions due to sources
c     istart to iend in the source array at the expansion centers
c     jstart to jend in the target array to the existing local
c     expansions
c
c     INPUT arguments
c------------------------------------------------------------------
c     nd           in: integer
c                  number of charge densities
c 
c     zk           in: double complex
c                  helmholtz parameter
c
c     istart       in:Integer
c                  Starting index in source array whose expansions
c                  we wish to add
c
c     iend         in:Integer
c                  Last index in source array whose expansions
c                  we wish to add
c
c     jstart       in: Integer
c                  First index in target array at which we
c                  wish to compute the expansions
c 
c     jend         in:Integer
c                  Last index in target array at which we wish
c                  to compute the expansions
c 
c     source       in: double precision(3,ns)
c                  Source locations
c
c     ifcharge     in: Integer
c                  flag for including expansions due to charges
c                  The expansion due to charges will be included
c                  if ifcharge == 1
c
c     charge       in: double complex
c                  Charge at the source locations
c
c     ifdipole     in: Integer
c                 flag for including expansions due to dipoles
c                 The expansion due to dipoles will be included
c                 if ifdipole == 1
c
c     dipstr        in: double complex(ns)
c                   dip strengths at the source locations
c
c     dipvec      in: double precision(3,ns)
c                 Dipole orientation vector at the source locations
c
c     targ        in: double precision(3,nexpc)
c                 Expansion center locations
c
c     scj         in: double precision(nexpc)
c                 scaling parameters for local expansions
c
c     ntj         in: Integer
c                 Number of terms in expansion
c
c     wlege       in: double precision(0:nlege,0:nlege)
c                 precomputed array of recurrence relation
c                 coeffs for Ynm calculation.
c
c    nlege        in: integer
c                 dimension parameter for wlege
c------------------------------------------------------------
c     OUTPUT
c
c   Updated expansions at the targets
c   texps : coeffs for local expansions
c-------------------------------------------------------               
        implicit none
c
        integer istart,iend,jstart,jend,ns,j, nlege
        integer nd
        integer ifcharge,ifdipole,ier
        double complex zk
        double precision source(3,*)
        double precision wlege(0:nlege,0:nlege)
        double complex charge(nd,*),dipstr(nd,*)
        double precision dipvec(nd,3,*)
        double precision targ(3,*),scj(*)

        integer nlevels,ntj
c
        double complex texps(nd,0:ntj,-ntj:ntj,*)
        
c
        ns = iend - istart + 1
        if(ifcharge.eq.1.and.ifdipole.eq.0) then
          do j=jstart,jend
            call h3dformtac(nd,zk,scj(j),
     1        source(1,istart),charge(1,istart),ns,
     2        targ(1,j),ntj,texps(1,0,-ntj,j),wlege,nlege)
           enddo
         endif

         if(ifcharge.eq.1.and.ifdipole.eq.1) then
          do j=jstart,jend
            call h3dformtacd(nd,zk,scj(j),
     1        source(1,istart),charge(1,istart),dipstr(1,istart),
     2        dipvec(1,1,istart),ns,targ(1,j),ntj,texps(1,0,-ntj,j),
     3        wlege,nlege)
           enddo
         endif

c
        return
        end
c------------------------------------------------------------------     
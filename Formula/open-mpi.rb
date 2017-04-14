class OpenMpi < Formula
  desc "High performance message passing library"
  homepage "https://www.open-mpi.org/"
  url "https://www.open-mpi.org/software/ompi/v2.1/downloads/openmpi-2.1.0.tar.bz2"
  sha256 "b169e15f5af81bf3572db764417670f508c0df37ce86ff50deb56bd3acb43957"

  bottle do
    sha256 "980dee19a68a35981cebdead7c7d7fa66df9b206481d8759c4738da884eb8952" => :sierra
    sha256 "0f22b4624cb270647bd806a165b12d907b50dec400707d8c3ead64f7eb07fa94" => :el_capitan
    sha256 "5ae27358f9df385b8ca9a2480f1ab99caf7a6ea9c8c14cfc118199364e532954" => :yosemite
  end

  head do
    url "https://github.com/open-mpi/ompi.git"
    depends_on "automake" => :build
    depends_on "autoconf" => :build
    depends_on "libtool" => :build
  end

  option "with-mpi-thread-multiple", "Enable MPI_THREAD_MULTIPLE"
  option "with-cxx-bindings", "Enable C++ MPI bindings (deprecated as of MPI-3.0)"
  option "with-peruse", "Enable MPI performance revealing extension interface (PERUSE)"
  option :cxx11

  deprecated_option "disable-fortran" => "without-fortran"
  deprecated_option "enable-mpi-thread-multiple" => "with-mpi-thread-multiple"

  depends_on :fortran => :recommended
  depends_on :java => :optional
  depends_on "libevent"

  conflicts_with "mpich", :because => "both install mpi__ compiler wrappers"
  conflicts_with "lcdf-typetools", :because => "both install same set of binaries."

  patch :p1, :DATA

  def install
    ENV.cxx11 if build.cxx11?

    args = %W[
      --prefix=#{prefix}
      --disable-dependency-tracking
      --disable-silent-rules
      --enable-ipv6
      --with-libevent=#{Formula["libevent"].opt_prefix}
      --with-sge
    ]
    args << "--with-platform-optimized" if build.head?
    args << "--disable-mpi-fortran" if build.without? "fortran"
    args << "--enable-mpi-thread-multiple" if build.with? "mpi-thread-multiple"
    args << "--enable-mpi-java" if build.with? "java"
    args << "--enable-mpi-cxx" if build.with? "cxx-bindings"
    args << "--enable-peruse" if build.with? "peruse"

    system "./autogen.pl" if build.head?
    system "./configure", *args
    system "make", "all"
    system "make", "check"
    system "make", "install"

    # If Fortran bindings were built, there will be stray `.mod` files
    # (Fortran header) in `lib` that need to be moved to `include`.
    if build.with? "fortran"
      include.install Dir["#{lib}/*.mod"]
    end
  end

  test do
    (testpath/"hello.c").write <<-EOS.undent
      #include <mpi.h>
      #include <stdio.h>

      int main()
      {
        int size, rank, nameLen;
        char name[MPI_MAX_PROCESSOR_NAME];
        MPI_Init(NULL, NULL);
        MPI_Comm_size(MPI_COMM_WORLD, &size);
        MPI_Comm_rank(MPI_COMM_WORLD, &rank);
        MPI_Get_processor_name(name, &nameLen);
        printf("[%d/%d] Hello, world! My name is %s.\\n", rank, size, name);
        MPI_Finalize();
        return 0;
      }
    EOS
    system bin/"mpicc", "hello.c", "-o", "hello"
    system "./hello"
    system bin/"mpirun", "-np", "4", "./hello"
    (testpath/"hellof.f90").write <<-EOS.undent
      program hello
      include 'mpif.h'
      integer rank, size, ierror, tag, status(MPI_STATUS_SIZE)
      call MPI_INIT(ierror)
      call MPI_COMM_SIZE(MPI_COMM_WORLD, size, ierror)
      call MPI_COMM_RANK(MPI_COMM_WORLD, rank, ierror)
      print*, 'node', rank, ': Hello Fortran world'
      call MPI_FINALIZE(ierror)
      end
    EOS
    system bin/"mpif90", "hellof.f90", "-o", "hellof"
    system "./hellof"
    system bin/"mpirun", "-np", "4", "./hellof"
  end
end

__END__
diff --git a/ompi/mca/pml/ob1/pml_ob1_isend.c b/ompi/mca/pml/ob1/pml_ob1_isend.c
index 1e96cdcc78..02114b4db4 100644
--- a/ompi/mca/pml/ob1/pml_ob1_isend.c
+++ b/ompi/mca/pml/ob1/pml_ob1_isend.c
@@ -85,6 +85,8 @@ static inline int mca_pml_ob1_send_inline (const void *buf, size_t count,
     opal_convertor_t convertor;
     size_t size;
     int rc;
+    mca_pml_base_send_request_t *sendreq = NULL;
+    mca_pml_base_request_t *base_req = NULL;

     bml_btl = mca_bml_base_btl_array_get_next(&endpoint->btl_eager);
     if( NULL == bml_btl->btl->btl_sendi)
@@ -115,10 +117,26 @@ static inline int mca_pml_ob1_send_inline (const void *buf, size_t count,

     ob1_hdr_hton(&match, MCA_PML_OB1_HDR_TYPE_MATCH, dst_proc);

+    sendreq = (mca_pml_base_send_request_t*)opal_free_list_wait(&mca_pml_base_send_requests);
+    base_req = &sendreq->req_base;
+    base_req->req_comm = comm;
+    base_req->req_addr = (void *)buf;
+    base_req->req_count = count;
+    base_req->req_datatype = datatype;
+    base_req->req_peer = dst;
+    base_req->req_tag = tag;
+
+    PERUSE_TRACE_COMM_EVENT(PERUSE_COMM_REQ_XFER_BEGIN, base_req, PERUSE_SEND);
+
     /* try to send immediately */
     rc = mca_bml_base_sendi (bml_btl, &convertor, &match, OMPI_PML_OB1_MATCH_HDR_LEN,
                              size, MCA_BTL_NO_ORDER, MCA_BTL_DES_FLAGS_PRIORITY | MCA_BTL_DES_FLAGS_BTL_OWNERSHIP,
                              MCA_PML_OB1_HDR_TYPE_MATCH, NULL);
+
+    PERUSE_TRACE_COMM_EVENT(PERUSE_COMM_REQ_XFER_END, base_req, PERUSE_SEND);
+
+    opal_free_list_return_mt (&mca_pml_base_send_requests, (opal_free_list_item_t *)sendreq);
+
     if (count > 0) {
         opal_convertor_cleanup (&convertor);
     }

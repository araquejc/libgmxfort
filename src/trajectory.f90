! libgmxfort
! https://github.com/wesbarnett/libgmxfort
! Copyright (C) 2016 James W. Barnett

! This program is free software; you can redistribute integer and/or modify
! integer under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 2 of the License, or
! (at your option) any later version.

! This program is distributed in the hope that integer will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.

! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

module gmxfort_trajectory

    use, intrinsic :: iso_c_binding, only: C_PTR, C_CHAR, C_FLOAT, C_INT
    use gmxfort_index

    implicit none
    private

    type, public :: Frame
        real(C_FLOAT), allocatable :: xyz(:,:)
        integer(C_INT) :: NATOMS, STEP, STAT
        real(C_FLOAT) :: box(3,3), prec, time
    end type

    type, public :: Trajectory
        type(xdrfile), pointer :: xd
        type(Frame), allocatable :: frameArray(:)
        type(IndexFile) :: ndx
        integer :: NFRAMES
        integer :: NATOMS
    contains
        procedure :: open => trajectory_constructor
        procedure :: read => trajectory_read
        procedure :: read_next => trajectory_read_next
        procedure :: close => trajectory_close
        procedure :: x => trajectory_get_xyz
        procedure :: n => trajectory_get_natoms
        procedure :: b => trajectory_get_box
    end type

    ! the data type located in libxdrfile
    type, bind(C) :: xdrfile
      type(C_PTR) :: fp, xdr
      character(kind=C_CHAR) :: mode
      integer(C_INT) :: buf1, buf1size, buf2, buf2size
    end type xdrfile

    ! interface with libxdrfile
    interface 

      integer(C_INT) function read_xtc_natoms(filename,NATOMS) bind(C, name='read_xtc_natoms')
        import
        character(kind=C_CHAR), intent(in) :: filename
        integer(C_INT), intent(out) :: NATOMS
      end function

      type(C_PTR) function xdrfile_open(filename,mode) bind(C, name='xdrfile_open')
        import
        character(kind=C_CHAR), intent(in) :: filename(*), mode(*)
      end function

      integer(C_INT) function read_xtc(xd,NATOMS,STEP,time,box,x,prec) bind(C, name='read_xtc')
        import
        type(xdrfile), intent(in) :: xd
        integer(C_INT), intent(out) :: NATOMS, STEP
        real(C_FLOAT), intent(out) :: time, prec, box(*), x(*)
      end function

      integer(C_INT) function write_xtc(xd,NATOMS,STEP,time,box,x,prec) bind(C, name='write_xtc')
        import
        type(C_PTR), intent(in) :: xd
        integer(C_INT), value, intent(in) :: NATOMS, STEP
        real(C_FLOAT), intent(in) :: box(*), x(*)
        real(C_FLOAT), value, intent(in) :: time, prec
      end function

      integer(C_INT) function xdrfile_close(xd) bind(C,name='xdrfile_close')
        import
        type(xdrfile), intent(in) :: xd
      end function

    end interface

contains

    subroutine trajectory_constructor(this, filename_in, ndxfile)

        use, intrinsic :: iso_c_binding, only: C_NULL_CHAR, C_CHAR, c_f_pointer

        implicit none
        class(Trajectory), intent(inout) :: this
        type(C_PTR) :: xd_c
        character (len=*), intent(in) :: filename_in
        character (len=*), intent(in), optional :: ndxfile
        character (len=206) :: filename
        logical :: ex
        integer :: STAT

        if (present(ndxfile)) then
            call this%ndx%read(ndxfile)
        end if

        inquire(file=trim(filename_in), exist=ex)

        if (ex .eqv. .false.) then
            write(0,*)
            write(0,'(a)') "Error: "//trim(filename_in)//" does not exist."
            write(0,*)
            stop
        end if

        ! Set the file name to be read in for C.
        filename = trim(filename_in)//C_NULL_CHAR

        ! Get number of atoms in system and allocate xyzition array.
        STAT = read_xtc_natoms(filename, this%NATOMS)

        if (STAT .ne. 0) then
            write(0,*)
            write(0,'(a)') "Error reading in "//trim(filename_in)//". Is it really an xtc file?"
            write(0,*)
            stop
        end if

        ! Open the file for reading. Convert C pointer to Fortran pointer.
        xd_c = xdrfile_open(filename,"r")
        call c_f_pointer(xd_c, this % xd)

        write(0,'(a)') "Opened "//trim(filename)//" for reading."
        write(0,'(i0,a)') this%NATOMS, " atoms present in system."
        write(0,*)

    end subroutine trajectory_constructor

    subroutine trajectory_read(this)

        implicit none
        class(Trajectory), intent(inout) :: this
        type(Frame), allocatable :: tmpFrameArray(:)
        real :: box_trans(3,3)
        integer :: STAT = 0
        integer :: I = 0

        do while (STAT .eq. 0)

            I = I + 1
            if (modulo(I, 10) .eq. 0) then
                write(0,'(a,i0)') achar(27)//"[1A"//achar(27)//"[K"//"Frame saved: ", I
            end if

            if (allocated(this%frameArray)) then
                allocate(tmpFrameArray(size(this%frameArray)+1))
                tmpFrameArray(1:size(this%frameArray)) = this%frameArray
                deallocate(this%frameArray)
                call move_alloc(tmpFrameArray, this%frameArray)
            else
                allocate(this%frameArray(1))
            end if

            allocate(this%frameArray(I)%xyz(3,this%NATOMS))
            STAT = read_xtc(this%xd, this%frameArray(I)%NATOMS, this%frameArray(I)%STEP, this%frameArray(I)%time, box_trans, &
                this%frameArray(I)%xyz, this%frameArray(I)%prec)
            ! C is row-major, whereas Fortran is column major. Hence the following.
            this%frameArray(I)%box = transpose(box_trans)

        end do

        this%NFRAMES = I-1

    end subroutine trajectory_read

    function trajectory_read_next(this, F)

        implicit none
        integer :: trajectory_read_next
        class(Trajectory), intent(inout) :: this
        integer, intent(in), optional :: F
        integer :: N
        type(Frame), allocatable :: tmpFrameArray(:)
        real :: box_trans(3,3)
        integer :: STAT = 0
        integer :: I

        if (present(F)) then
            N = F
        else
            N = 1
        end if

        if (allocated(this%frameArray)) then
            deallocate(this%frameArray)
        end if
        allocate(this%frameArray(N))


        do I = 1, N

            allocate(this%frameArray(I)%xyz(3,this%NATOMS))
            STAT = read_xtc(this%xd, this%frameArray(I)%NATOMS, this%frameArray(I)%STEP, this%frameArray(I)%time, box_trans, &
                this%frameArray(I)%xyz, this%frameArray(I)%prec)
            ! C is row-major, whereas Fortran is column major. Hence the following.
            this%frameArray(I)%box = transpose(box_trans)

            if (STAT .ne. 0) then
                exit
            end if

        end do

        this%NFRAMES = I-1
        trajectory_read_next = this%NFRAMES

    end function trajectory_read_next

    subroutine trajectory_close(this)

        implicit none
        class(Trajectory), intent(inout) :: this
        integer :: STAT

        STAT = xdrfile_close(this % xd)

    end subroutine trajectory_close

    function trajectory_get_xyz(this, frame, atom, group)

        implicit none
        real :: trajectory_get_xyz(3)
        integer, intent(in) :: frame
        integer, intent(in) :: atom
        class(Trajectory), intent(inout) :: this
        character (len=*), intent(in), optional :: group

        if (present(group)) then
            trajectory_get_xyz = this%frameArray(frame)%xyz(:,this%ndx%get(group,atom))
        else
            trajectory_get_xyz = this%frameArray(frame)%xyz(:,atom)
        end if

    end function trajectory_get_xyz

    function trajectory_get_natoms(this, group)

        implicit none
        integer :: trajectory_get_natoms
        class(Trajectory), intent(in) :: this
        character (len=*), intent(in), optional :: group

        if (present(group)) then
            trajectory_get_natoms = this%ndx%get_natoms(group)
        else
            trajectory_get_natoms = this%NATOMS
        end if

    end function trajectory_get_natoms

    function trajectory_get_box(this, frame)

        implicit none
        real(8) :: trajectory_get_box(3,3)
        class(Trajectory), intent(in) :: this
        integer, intent(in) :: frame

        trajectory_get_box = this%frameArray(frame)%box

    end function trajectory_get_box

end module gmxfort_trajectory

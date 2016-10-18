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


module gmxfort_index

    implicit none
    private

    type ndxgroups
        integer, allocatable :: LOC(:)
        integer :: NUMATOMS
        character (len=:), allocatable :: title
    end type ndxgroups

    type, public :: IndexFile
        type (ndxgroups), allocatable :: group(:)
    contains
        procedure :: read => indexfile_read
        procedure :: get => indexfile_get
        procedure :: get_natoms => indexfile_get_natoms
    end type IndexFile
 
contains

    subroutine indexfile_read(this, filename)
        implicit none
        class(IndexFile), intent(inout) :: this
        character (len=*), intent(in) :: filename
        character (len=2048) :: line
        integer :: INDEX_FILE_UNIT
        integer :: IO_STATUS
        integer :: LEFTBRACKET_INDEX
        integer :: RIGHTBRACKET_INDEX
        integer :: NGRPS = 0
        integer, allocatable :: INDICES_TMP(:)
        integer, allocatable :: TITLE_LOC(:)
        integer, allocatable :: TMP(:)
        integer :: I, J
        logical :: ex

        ! Does the file exist?
        inquire(file=trim(filename), exist=ex)
        if (ex .eqv. .false.) then
            write(0, '(a)') "ERROR: "//trim(filename)//" does not exist."
            stop
        end if

        ! Is in index file?
        open(newunit=INDEX_FILE_UNIT, file=trim(filename), status="old")
        read(INDEX_FILE_UNIT, '(a)', iostat=IO_STATUS) line
        LEFTBRACKET_INDEX = index(line, "[")
        if (LEFTBRACKET_INDEX .eq. 0) then
            write(0, '(a)') "ERROR: "//trim(filename)//" is not a valid index file."
            stop
        end if

        ! How many groups are in it?
        rewind INDEX_FILE_UNIT
        IO_STATUS = 0
        do while (IO_STATUS .eq. 0)

            read(INDEX_FILE_UNIT, '(a)', iostat=IO_STATUS) line
            LEFTBRACKET_INDEX = index(line, "[")
            if (LEFTBRACKET_INDEX .ne. 0) then
                NGRPS = NGRPS + 1 
            end if

        end do

        allocate(this%group(NGRPS))
        allocate(TITLE_LOC(NGRPS+1)) ! Add one to include end of file

        ! Now find the title locations and save their names
        rewind INDEX_FILE_UNIT
        I = 1
        J = 1
        IO_STATUS = 0
        do while (IO_STATUS .eq. 0)

            read(INDEX_FILE_UNIT, '(a)', iostat=IO_STATUS) line
            LEFTBRACKET_INDEX = index(line, "[")
            RIGHTBRACKET_INDEX = index(line, "]")
            if (LEFTBRACKET_INDEX .ne. 0) then
                this%group(I)%title = trim(line(LEFTBRACKET_INDEX+2:RIGHTBRACKET_INDEX-2))
                TITLE_LOC(I) = J
                I = I + 1
            end if
            J = J + 1

        end do
        TITLE_LOC(I) = J-1 ! End of file location

        rewind INDEX_FILE_UNIT

        ! Now finally get all of the indices for each group
        do I = 1, NGRPS
            allocate(INDICES_TMP((TITLE_LOC(I+1)-TITLE_LOC(I)-1)*15))
            read(INDEX_FILE_UNIT, '(a)', iostat=IO_STATUS) line
            LEFTBRACKET_INDEX = index(line, "[")
            do while  (LEFTBRACKET_INDEX .eq. 0)
                backspace INDEX_FILE_UNIT
                backspace INDEX_FILE_UNIT
                read(INDEX_FILE_UNIT, '(a)', iostat=IO_STATUS) line
                LEFTBRACKET_INDEX = index(line, "[")
            end do
            INDICES_TMP = -1
            read(INDEX_FILE_UNIT, *, iostat=IO_STATUS) INDICES_TMP
            if (minval(INDICES_TMP) .eq. -1) then
                allocate(TMP(size(minloc(INDICES_TMP))))
                TMP = minloc(INDICES_TMP)
                allocate(this%group(I)%LOC(TMP(1)-1))
                this%group(I)%LOC = INDICES_TMP(1:TMP(1)-1)
                this%group(I)%NUMATOMS = TMP(1)-1
                deallocate(TMP)
            else
                this%group(I)%LOC = INDICES_TMP
            end if
            deallocate(INDICES_TMP)
        end do
        close(INDEX_FILE_UNIT)
        
    end subroutine indexfile_read

    function indexfile_get(this, group_name, I)

        implicit none
        integer :: indexfile_get
        class(IndexFile), intent(inout) :: this
        character (len=*), intent(in) :: group_name
        integer, intent(in) :: I
        integer :: J

        do J = 1, size(this%group)

            if (this%group(J)%title .eq. group_name) then

                indexfile_get = this%group(J)%LOC(I)
                return

            end if

        end do

        write(0, '(a)') "ERROR: "//trim(group_name)//" is not in index file."
        stop

    end function indexfile_get

    function indexfile_get_natoms(this, group_name)

        implicit none
        integer indexfile_get_natoms
        class(IndexFile), intent(in) :: this
        character (len=*) :: group_name
        integer :: J

        do J = 1, size(this%group)

            if (this%group(J)%title .eq. group_name) then

                indexfile_get_natoms = this%group(J)%NUMATOMS
                return

            end if

        end do

        write(0, '(a)') "ERROR: "//trim(group_name)//" is not in index file."
        stop
        

    end function indexfile_get_natoms

end module gmxfort_index


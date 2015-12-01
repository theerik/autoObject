#!/bin/sh
# -*- tcl -*-
# The next line is executed by /bin/sh, but not tcl \
exec tclsh "$0" ${1+"$@"}

#--------------------------------------------------------------------------
#
# FILENAME:    autoObjectData.tcl
#
# AUTHOR:      theerik@github
#
# DESCRIPTION:  AutoObject is a base class used to create auto-assembling
#               objects using a descriptor array.  AutoObjectData defines
#               a base class and many common derived classes used as field
#               types within an AutoObject.  Common types defined include:
#                   * uint8_t
#                   * uint16_t
#                   * uint32_t
#                   * uint16_bt (Big-endian)
#                   * uint32_bt (Big-endian)
#                   * int8_t
#                   * int16_t
#                   * int32_t
#                   * int16_bt  (Big-endian)
#                   * int32_bt  (Big-endian)
#                   * float_t
#                   * time_t    (Unix system time)

#                   * string_t
#
#--------------------------------------------------------------------------
#
# Copyright 2015, Erik N. Johnson
#
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
#  autoData classes
#
# All types used as AutoObject fields must support the following
# canonical methods:
#   * get
#   * set
#   * toList
#   * fromList
#   * toString
# All classes should be declared in the ::AutoData:: namespace, as below.
# To allow the "follow" method of the autoObject to work, the actual data
# value should be held in the canonical name "MyValue".

#--------------------------------------------------------------------------
#   uint8_t
#
oo::class create ::AutoData::uint8_t {
    variable MyValue

    constructor {args} { set MyValue 0 }
    method get {} { return $MyValue }
    method set {newVal} { set MyValue $newVal }
    method toString {} { return [format "%3d" $MyValue] }
    method toList {} { return [format "%d" [expr {$MyValue % 256}]] }
    method fromList {inList} { set MyValue [expr {[lindex $inList 0] % 256}] }
}

#--------------------------------------------------------------------------
#   int8_t
#
oo::class create ::AutoData::int8_t {
    superclass ::AutoData::uint8_t

    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x80} {
            set MyValue [expr {$MyValue - 256}]
        }
    }
}

#--------------------------------------------------------------------------
#   uint16_t
#
oo::class create ::AutoData::uint16_t {
    variable MyValue

    constructor {args} { set MyValue 0 }
    method get {} { return $MyValue }
    method set {newVal} { set MyValue $newVal }
    method toString {} { return [format "%5d" $MyValue] }
    method toList {} {
        set outL [format "%d" [expr {$MyValue & 0x00FF}]]
        lappend outL [format "%d" [expr {($MyValue & 0xFF00) >> 8}]]
        return $outL
    }
    method fromList {inList} {
        set MyValue [expr {[format "0x%02x%02x" {*}[lreverse \
                                                    [lrange $inList 0 1]]]}]
    }
}

#--------------------------------------------------------------------------
#   uint16_bt
#
# Same as uint16_t except big-endian in list format
oo::class create ::AutoData::uint16_bt {
    superclass ::AutoData::uint16_t

    method toList {} {
        set outL [format "%d" [expr {($MyValue & 0xFF00) >> 8}]]
        lappend outL [format "%d" [expr {$MyValue & 0x00FF}]]
        return $outL
    }
    method fromList {inList} {
        set MyValue [expr {[format "0x%02x%02x" {*}[lrange $inList 0 1]]}]
    }
}

#--------------------------------------------------------------------------
#   int16_t
#
oo::class create ::AutoData::int16_t {
    superclass ::AutoData::uint16_t

    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x8000} {
            set MyValue [expr {$MyValue - 65536}]
        }
    }
}

#--------------------------------------------------------------------------
#   int16_bt
#
oo::class create ::AutoData::int16_bt {
    superclass ::AutoData::uint16_bt

    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x8000} {
            set MyValue [expr {$MyValue - 65536}]
        }
    }
}

#--------------------------------------------------------------------------
#   uint32_t
#
oo::class create ::AutoData::uint32_t {
    variable MyValue

    constructor {args} { set MyValue 0 }
    method get {} { return $MyValue }
    method set {newVal} { set MyValue $newVal }
    method toString {} { return [format "%10d" $MyValue] }
    method toList {} {
        set outL     [format "%d" [expr { $MyValue & 0x000000FF}]]
        lappend outL [format "%d" [expr {($MyValue & 0x0000FF00) >> 8}]]
        lappend outL [format "%d" [expr {($MyValue & 0x00FF0000) >> 16}]]
        lappend outL [format "%d" [expr {($MyValue & 0xFF000000) >> 24}]]
        return $outL
    }
    method fromList {inList} {
        set MyValue [expr {[format "0x%02x%02x%02x%02x" {*}[lreverse \
                                                    [lrange $inList 0 3]]]}]
    }
}

#--------------------------------------------------------------------------
#   uint32_bt
#
# Same as uint32_t except big-endian in list format
oo::class create ::AutoData::uint32_bt {
    superclass ::AutoData::uint32_t

    method toList {} {
        set outL     [format "%d" [expr {($MyValue & 0xFF000000) >> 24}]]
        lappend outL [format "%d" [expr {($MyValue & 0x00FF0000) >> 16}]]
        lappend outL [format "%d" [expr {($MyValue & 0x0000FF00) >> 8}]]
        lappend outL [format "%d" [expr { $MyValue & 0x000000FF}]]
        return $outL
    }
    method fromList {inList} {
        set MyValue [expr {[format "0x%02x%02x%02x%02x" {*}[lrange $inList 0 3]]}]
    }
}

#--------------------------------------------------------------------------
#   int32_t
#
oo::class create ::AutoData::int32_t {
    superclass ::AutoData::uint32_t

    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x80000000} {
            set MyValue [expr {$MyValue - 2147483648}]
        }
    }
}

#--------------------------------------------------------------------------
#   int32_bt
#
oo::class create ::AutoData::int32_bt {
    superclass ::AutoData::uint32_bt

    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x80000000} {
            set MyValue [expr {$MyValue - 2147483648}]
        }
    }
}

#--------------------------------------------------------------------------
#   float_t
#
oo::class create ::AutoData::float_t {
    variable MyValue

    constructor {args} { set MyValue 0.0 }
    method get {} { return $MyValue }
    method set {newVal} {
        if [catch {set MyValue [expr {$newVal + 0.0}]} errS] {
            alert "$newVal is Not a Number!  ($errS)"
            set MyValue "NaN"
        }
    }
    method toString {} {
        if [catch {set outS [format %8f $MyValue]}] {
            alert "$MyValue is Not a Number!"
        }
        return $outS
    }
    method toList {} {
        # Convert using the native float format.  N.B. this works only
        # when the target & x86 use the same float format.
        binary scan [binary format f $MyValue] c* outL
        return $outL
    }
    method fromList {inList} {
        # Convert using the native float format.  N.B. this works only
        # when the target & x86 use the same float format.
        binary scan [binary format c4 $inList] f value
        set MyValue $value
    }
}

#--------------------------------------------------------------------------
#   time_t
#
# Time is stored internally as a Unix time_t - a 32-bit count of seconds
# since the Unix epoch (Jan 1, 1970).  The set method will accept an integer
# directly, or if passed a non-integer will attempt to parse it using
# clock scan.  If that fails, it allows clock scan to throw the error.
# Since it's stored as a 32-bit int, most methods act as the uint32_t
# superclass.
#
# The Constructor can be passed a default time format string to be used when
# stringifying; we also add a method to set the default string later.
# toString accepts a format string; if one is not provided it uses the
# default string set earlier.
oo::class create ::AutoData::time_t {
    superclass ::AutoData::uint32_t
    variable MyFormatStr

    constructor {args} {
        my variable MyValue
        # default value for a new time object is "now".
        set MyValue [clock seconds]
        if {$args ne ""} {
            set MyFormatStr $args
        } else {
            set MyFormatStr "%B %d, %Y at %H:%M:%S"
        }
    }
    method set {newVal} {
        my variable MyValue
        if {![string is integer -strict $newVal]} {
           set MyValue [clock scan $newVal]
        } else {
            set MyValue $newVal
        }
    }
    method setFormat {newFmtStr} {
        set MyFormatStr $newFmtStr
    }
    method toString {args} {
        my variable MyValue
        if {$args ne ""} {
            set fmtStr $args
        } else {
            set fmtStr $MyFormatStr
        }
        return [clock format $MyValue -format $fmtStr]
    }
}

#--------------------------------------------------------------------------
#   string_t
#
# N.B. This class expects the length of the field to be passed in on creation
# as an additional argument.  If not provided, the constructor will fail.
#
# The string_t autoData type is constrained by the length of its field.  It
# will truncate any attempt to set it to longer to the first N characters that
# will fit into that field length.  If the input is shorter, the string will
# be null terminated and filled with NULLs in the line format.
oo::class create ::AutoData::string_t {
    variable MyValue MyLength

    constructor {args} {
        if {![string is digit -strict [lindex $args 0]]} {
            error "String_t constructor error: \
                   field length not specified in defining list."
        }
        set MyLength [lindex $args 0]
        set MyValue ""
    }
    method get {} { return $MyValue }
    method set {newVal} {
        set MyValue [string range $newVal 0 [expr {$MyLength - 1}] ]
    }
    method toString {} { return $MyValue }
    method toList {} {
        binary scan $MyValue c* dataL
        if {[llength $dataL] < $MyLength} {
            lappend dataL {*}[lrepeat [expr {$MyLength - [llength $dataL]}] 0]
        }
        return $dataL
    }
    method fromList {inList} {
        set MyValue [string trimright [binary format c* $inList] '\0']
    }
}

#--------------------------------------------------------------------------
#   unicode_t
#
# N.B. This class expects the length of the field *IN CHARACTERS* to be
# passed in on creation as an additional argument.  This is different from
# the length in bytes, as characters are allocated 2 bytes each.
# If not provided, the constructor will fail.  If the length is incorrect,
# the list/byte formats produced will not be the correct length.
#
# The unicode_t autoData type is constrained by the length of its field.  It
# will truncate any attempt to set it to longer to the first N characters that
# will fit into that field length.  If the input is shorter, the string will
# be null terminated and filled with NULLs in the line format.
oo::class create ::AutoData::unicode_t {
    superclass ::AutoData::string_t
    variable MyValue MyLength

    method toList {} {
        binary scan [encoding convertto unicode $MyValue] c* dataL
        if {[llength $dataL] < [expr {$MyLength * 2}} {
            lappend dataL {*}[lrepeat [expr {$MyLength * 2 - [llength $dataL]}] 0]
        }
        return $dataL
    }
    method fromList {inList} {
        set MyValue [string trimright [encoding convertfrom unicode \
                                       [binary format c* $inList]] '\0']
    }
}
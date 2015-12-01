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

#                   * string_t
#                   * time_t    (Unix system time)
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

#--------------------------------------------------------------------------
#   Auto_uint8_t
#
oo::class create ::AutoData::Auto_uint8_t {
    variable MyValue

    constructor {args} { set MyValue 0 }
    method get {} { return $MyValue }
    method set {newVal} { set MyValue $newVal }
    method toString {} { return [format "%3d" $MyValue] }
    method toList {} { return [format "%d" [expr {$MyValue % 256}]] }
    method fromList {inList} { set MyValue [expr {[lindex $inList 0] % 256}] }
}

#--------------------------------------------------------------------------
#   Auto_int8_t
#
oo::class create ::AutoData::Auto_int8_t {
    superclass ::AutoData::Auto_uint8_t

    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x80} {
            set MyValue [expr {$MyValue - 256}]
        }
    }
}

#--------------------------------------------------------------------------
#   Auto_uint16_t
#
oo::class create ::AutoData::Auto_uint16_t {
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
#   Auto_uint16_bt
#
# Same as uint16_t except big-endian in list format
oo::class create ::AutoData::Auto_uint16_bt {
    superclass ::AutoData::Auto_uint16_t

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
#   Auto_int16_t
#
oo::class create ::AutoData::Auto_int16_t {
    superclass ::AutoData::Auto_uint16_t

    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x8000} {
            set MyValue [expr {$MyValue - 65536}]
        }
    }
}

#--------------------------------------------------------------------------
#   Auto_int16_bt
#
oo::class create ::AutoData::Auto_int16_bt {
    superclass ::AutoData::Auto_uint16_bt

    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x8000} {
            set MyValue [expr {$MyValue - 65536}]
        }
    }
}

#--------------------------------------------------------------------------
#   Auto_uint32_t
#
oo::class create ::AutoData::Auto_uint32_t {
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
#   Auto_uint32_bt
#
# Same as uint32_t except big-endian in list format
oo::class create ::AutoData::Auto_uint32_bt {
    superclass ::AutoData::Auto_uint32_t

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
#   Auto_int32_t
#
oo::class create ::AutoData::Auto_int32_t {
    superclass ::AutoData::Auto_uint32_t

    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x80000000} {
            set MyValue [expr {$MyValue - 2147483648}]
        }
    }
}

#--------------------------------------------------------------------------
#   Auto_int32_bt
#
oo::class create ::AutoData::Auto_int32_bt {
    superclass ::AutoData::Auto_uint32_bt

    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x80000000} {
            set MyValue [expr {$MyValue - 2147483648}]
        }
    }
}

#--------------------------------------------------------------------------
#   Auto_float_t
#
oo::class create ::AutoData::Auto_float_t {
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
#   Auto_time_t
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
oo::class create ::AutoData::Auto_time_t {
    superclass ::AutoData::Auto_uint32_t
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


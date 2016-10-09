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
# Copyright 2015-16, Erik N. Johnson
#
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
#  autoData classes
#
# All types used as AutoObject fields *must* support the following
# canonical methods:
#   * get
#   * set
#   * toList
#   * fromList
#   * toString
# All classes should be declared in the ::AutoObject:: namespace, as below.
# To allow the "follow" method of the autoObject to work, the actual data
# value should be held in the canonical name "MyValue".  If the data value
# is not held in MyValue, the follow method should be redefined for the
# containing class to behave correctly.

#--------------------------------------------------------------------------
#   uint8_t
#
oo::class create ::AutoObject::uint8_t {
    variable MyValue

    constructor {args} { set MyValue 0 }
    method get {} { return $MyValue }
    method set {newVal} { set MyValue [expr {$newVal % 256}]}
    method toString {} { return [format "%-3d" $MyValue] }
    method toList {} { return [format "%d" [expr {$MyValue % 256}]] }
    method fromList {inVal} { set MyValue [expr {$inVal % 256}] }
}

#--------------------------------------------------------------------------
#   int8_t
#
oo::class create ::AutoObject::int8_t {
    superclass ::AutoObject::uint8_t

    method set {newVal} { 
        my variable MyValue
        set MyValue $newVal
    }
    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x80} {
            incr MyValue -256
        }
    }
}

#--------------------------------------------------------------------------
#   uint16_t
#
oo::class create ::AutoObject::uint16_t {
    variable MyValue

    constructor {args} { set MyValue 0 }
    method get {} { return $MyValue }
    method set {newVal} { set MyValue [expr {$newVal % 65536}] }
    method toString {} { return [format "%-5d" $MyValue] }
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
oo::class create ::AutoObject::uint16_bt {
    superclass ::AutoObject::uint16_t

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
oo::class create ::AutoObject::int16_t {
    superclass ::AutoObject::uint16_t

    method set {newVal} { 
        my variable MyValue
        set MyValue $newVal
    }
    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x8000} {
            incr MyValue -65536
        }
    }
}

#--------------------------------------------------------------------------
#   int16_bt
#
oo::class create ::AutoObject::int16_bt {
    superclass ::AutoObject::uint16_bt

    method set {newVal} { 
        my variable MyValue
        set MyValue $newVal
    }
    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x8000} {
            incr MyValue -65536
        }
    }
}

#--------------------------------------------------------------------------
#   uint32_t
#
oo::class create ::AutoObject::uint32_t {
    variable MyValue

    constructor {args} { set MyValue 0 }
    method get {} { return $MyValue }
    method set {newVal} { set MyValue [expr {$newVal % 4294967296}] }
    method toString {} { return [format "%-10d" $MyValue] }
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
oo::class create ::AutoObject::uint32_bt {
    superclass ::AutoObject::uint32_t

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
oo::class create ::AutoObject::int32_t {
    superclass ::AutoObject::uint32_t

    method set {newVal} { 
        my variable MyValue
        set MyValue $newVal
    }
    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x80000000} {
            incr MyValue -4294967296
        }
    }
}

#--------------------------------------------------------------------------
#   int32_bt
#
oo::class create ::AutoObject::int32_bt {
    superclass ::AutoObject::uint32_bt

    method set {newVal} { 
        my variable MyValue
        set MyValue $newVal
    }
    method fromList {inList} {
        my variable MyValue
        next $inList
        if {$MyValue & 0x80000000} {
            incr MyValue -4294967296
        }
    }
}

#--------------------------------------------------------------------------
#   float_t
#
oo::class create ::AutoObject::float_t {
    variable MyValue

    constructor {args} { set MyValue 0.0 }
    method get {} { return $MyValue }
    method set {newVal} {
        if [catch {set MyValue [expr {$newVal + 0.0}]} errS] {
            log::alert "$newVal is Not a Number!  ($errS)"
            set MyValue "NaN"
        }
    }
    method toString {} {
        if [catch {set outS [format %8f $MyValue]}] {
            log::alert "$MyValue is Not a Number!"
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
oo::class create ::AutoObject::time_t {
    superclass ::AutoObject::uint32_t
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
oo::class create ::AutoObject::string_t {
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
oo::class create ::AutoObject::unicode_t {
    superclass ::AutoObject::string_t
    variable MyValue MyLength

    method toList {} {
        binary scan [encoding convertto unicode $MyValue] c* dataL
        if {[llength $dataL] < [expr {$MyLength * 2}]} {
            lappend dataL {*}[lrepeat [expr {$MyLength * 2 - [llength $dataL]}] 0]
        }
        return $dataL
    }
    method fromList {inList} {
        set MyValue [string trimright [encoding convertfrom unicode \
                                       [binary format c* $inList]] '\0']
    }
}

#--------------------------------------------------------------------------
#   enum_mix
#
# N.B. This class is a mixin for classes based on the uint8_t class (or
# uint16_t or uint32_t if you need large fields for some reason).
# The host class is expected to provide most of the features, including any
# of the length-specific code; the mixin only provides an override for the
# "set" and "toString" methods.
#
# N.B. The enum_TYPE class is a bit of code clevverness that expects to be
# initialized before use.  The base class provides the mechanisms; initialization
# only provides the lookup table mapping the symbol to the enum value.  
# Without providing the definition of the enum, it's not very useful.
#
# To initialize, immediately after mixing it into the base class, invoke the
# "setEnumDef" method with a list consisting of name/value pairs.  Objects of
# the ensuing class will then accept the symbolic names of the enum as inputs
# to "set", and will print via "toString" the symbolic names.
#
oo::class create ::AutoObject::enum_mix {
    variable defArray

    method set {newVal} {
        my variable MyValue
        set ns [info object namespace [info object class [self object]]]
        upvar ${ns}::defArray defArray
        if {[info exists defArray($newVal)]} {
            set MyValue $defArray($newVal)
        } elseif {[info exists defArray(val-$newVal)]} {
            set MyValue $newVal
        } else {
            error "Tried to set enum [self] to unknown value $newVal"
        }
    }
    method toString {} {
        my variable MyValue
        set ns [info object namespace [info object class [self object]]]
        upvar ${ns}::defArray defArray
        return $defArray(val-$MyValue)
    }
}
proc ::AutoObject::setEnumDef {classname defL} {
    namespace upvar [info object namespace $classname] defArray dA
    array set dA $defL
    foreach {key val} [array get dA] {
        set dA(val-$val) $key
    }
}


#--------------------------------------------------------------------------
#   bitfield_mix
#
# N.B. This class is a mixin for classes based on the uint8_t class (or
# uint16_t or uint32_t if you need large fields for some reason).
# The host class is expected to provide most of the features, including any
# of the length-specific code; the mixin only provides an override for the
# "set", "get" and "toString" methods.
#
# N.B. The bitfield_TYPE class is a bit of code clevverness that expects to be
# initialized before use.  The base class provides the mechanisms; 
# initialization only provides the lookup table mapping the fields to the bits.
# Without providing the definition of the enum, it's not very useful.
#
# To initialize, immediately after mixing it into the base class, invoke the
# "setBitfieldDef" method with a list consisting of field definition lists,
# where each field definition is the name, number of bits, and (optional)
# enum value of the bit combinations (in order 0 -> max).  
#
oo::class create ::AutoObject::bitfield_mix {
    variable ns

    method get {args} {
        my variable MyValue
        set ns [info object namespace [info object class [self object]]]
        upvar ${ns}::defArray defArray
        if {[llength $args] == 0} {
            return $MyValue
        } else {
            set outL {}
            foreach field $args {
                set val [expr ($MyValue & $defArray($field,mask) ) \
                                    >> $defArray($field,shift)]
                lappend outL $val
            }
            return $outL
        }
    }
    method set {args} {
        my variable MyValue
        set ns [info object namespace [info object class [self object]]]
        upvar ${ns}::defArray defArray
        set len [llength $args]
        if {$len == 1} {
            # setting entire value
            set MyValue $args
        } elseif {$len % 2 == 0} {
            # If setting fields, must be a list of field/value pairs
            foreach {key val} $args {
                # If there is an enum and the input is a symbol, use its value
                if {[info exists defArray($key,enumL)] && \
                        ($val in $defArray($key,enumL))} {
                    set val [lsearch $defArray($key,enumL) $val]
                }
                set MyValue [expr ($MyValue & ~$defArray($key,mask)) | \
                                    (($val << $defArray($key,shift)) & \
                                    $defArray($key,mask))]
            }
        } else {
            error "Odd number of items in key/value list: $args"
        }
    }
    method toString {} {
        my variable MyValue
        set ns [info object namespace [info object class [self object]]]
        upvar ${ns}::defArray defArray
        set outS ""
        set newline ""
        set nameSize [expr [string length [lindex $defArray(nameL) 0]] + 44]
        set outS [format "%s  Decoded to:\n" [next]]
        foreach name $defArray(nameL) {
            set val [expr ($MyValue & $defArray($name,mask)) \
                                    >> $defArray($name,shift)]
            # If there's an enum, print the symbol
            if {[info exists defArray($name,enumL)] && \
                    $val < [llength $defArray($name,enumL)]} {
                set valS [lindex $defArray($name,enumL) $val]
            } else {
                set size $defArray($name,size)
                set valS [format "b'%0${size}b" $val]
            }
            append outS [format "%${nameSize}s - %s\n" $name $valS]
        }
        # trim to display multiline output properly in autoObject output
        set outS [string trimright $outS "\n"]
        return $outS
    }
}
proc ::AutoObject::setBitfieldDef {classname defL} {
    namespace upvar [info object namespace $classname] defArray dA
    set offset 0
    foreach bf $defL {
        set name [lindex $bf 0]
        lappend nameL $name
        set size [lindex $bf 1]
        set dA($name,size) $size
        if {[llength $bf] > 2} {
            set dA($name,enumL) [lindex $bf 2]
        }
        set maskS [string repeat "1" $size]
        append maskS [string repeat "0" $offset]
        scan $maskS "%b" mask
        set dA($name,shift) $offset
        set dA($name,mask) $mask
        set offset [expr {$offset + $size}]
    }
    set dA(nameL) $nameL
}
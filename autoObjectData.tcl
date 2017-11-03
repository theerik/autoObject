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
#
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
###########################################################################
#
# Copyright 2015-17, Erik N. Johnson
#
# This package documentation is auto-generated with
# Pycco: <https://pycco-docs.github.io/pycco/>
#
# Use "pycco filename" to re-generate HTML documentation in ./docs .
#

#--------------------------------------------------------------------------
###  autoData classes
#
# All types used as AutoObject fields *must* support the following
# canonical methods:
#
#   * get
#   * set
#   * toList
#   * fromList
#   * toString
#
# Optional methods used primarily for GUI building are:
#
# *  follow
# *  createWidget
#
# If a subclassing application needs additional methods, the base classes
# can be extended by defining additional methods either on the class or on
# the objects.
#
# All new classes should be declared in the ::AutoObject:: namespace, as
# below. To allow the "follow" method of the base autoObject containing class
# to work correctly, the actual data value should be held in the canonical
# name "MyValue".  If the data value is not held in MyValue, the follow method
# should be redefined for the containing class to behave correctly, or
# only invoked on the field object (harder to ensure).
#

#--------------------------------------------------------------------------
####   uint8_t
#
# The most basic field type, a single byte of unsigned data.
#
oo::class create ::AutoObject::uint8_t {
    variable MyValue MyWidget

    constructor {args} { set MyValue 0 }
    method get {} { return $MyValue }
    method set {newVal} { set MyValue [expr {$newVal % 256}]}
    method toString {} { return [format "%-3d" $MyValue] }
    method toList {} { return [format "%d" [expr {$MyValue % 256}]] }
    method fromList {inList} {
        set MyValue [expr {[lindex $inList 0] % 256}]
        return [lrange $inList 1 end]
    }
}

#--------------------------------------------------------------------------
####   int8_t
#
# A single byte of signed data.
# Since list data is effectively unsigned, perform the final 2's complement
# on the MSbit, and don't force the *set* method to an unsigned value.
#
oo::class create ::AutoObject::int8_t {
    superclass ::AutoObject::uint8_t

    method set {newVal} {
        my variable MyValue
        set MyValue $newVal
    }
    method fromList {inList} {
        my variable MyValue
        set outL [next $inList]
        if {$MyValue & 0x80} {
            incr MyValue -256
        }
        return $outL
    }
}

#--------------------------------------------------------------------------
####   uint16_t
#
# Two bytes of data, where the byte list is interpreted as a single unsigned
# number in little-endian format.
#
oo::class create ::AutoObject::uint16_t {
    variable MyValue MyWidget

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
        return [lrange $inList 2 end]
    }
}

#--------------------------------------------------------------------------
####   uint16_bt
#
# Same as *uint16_t* except big-endian in byte list format.
#
oo::class create ::AutoObject::uint16_bt {
    superclass ::AutoObject::uint16_t

    method toList {} {
        set outL [format "%d" [expr {($MyValue & 0xFF00) >> 8}]]
        lappend outL [format "%d" [expr {$MyValue & 0x00FF}]]
        return $outL
    }
    method fromList {inList} {
        set MyValue [expr {[format "0x%02x%02x" {*}[lrange $inList 0 1]]}]
        return [lrange $inList 2 end]
    }
}

#--------------------------------------------------------------------------
####   int16_t
#
# Same as *uint16_t* except the value is interpreted as signed.
# Since list data is effectively unsigned, perform the final 2's complement
# on the MSbit, and don't force the *set* method to an unsigned value.
#
oo::class create ::AutoObject::int16_t {
    superclass ::AutoObject::uint16_t

    method set {newVal} {
        my variable MyValue
        set MyValue $newVal
    }
    method fromList {inList} {
        my variable MyValue
        set outL [next $inList]
        if {$MyValue & 0x8000} {
            incr MyValue -65536
        }
        return $outL
    }
}

#--------------------------------------------------------------------------
####   int16_bt
#
# Same as *uint16_t* except the list is interpreted as big-endian and the
# value is interpreted as signed.
# Since list data is effectively unsigned, perform the final 2's complement
# on the MSbit, and don't force the *set* method to an unsigned value.
#
oo::class create ::AutoObject::int16_bt {
    superclass ::AutoObject::uint16_bt

    method set {newVal} {
        my variable MyValue
        set MyValue $newVal
    }
    method fromList {inList} {
        my variable MyValue
        set outL [next $inList]
        if {$MyValue & 0x8000} {
            incr MyValue -65536
        }
        return $outL
    }
}

#--------------------------------------------------------------------------
####   uint32_t
#
# Four bytes of data, where the byte list is interpreted as a single unsigned
# number in little-endian format.
#
oo::class create ::AutoObject::uint32_t {
    variable MyValue MyWidget

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
        return [lrange $inList 4 end]
    }
}

#--------------------------------------------------------------------------
####   uint32_bt
#
# Same as *uint32_t* except big-endian in byte list format.
#
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
        return [lrange $inList 4 end]
    }
}

#--------------------------------------------------------------------------
####   int32_t
#
# Same as *uint32_t* except the value is interpreted as signed.
# Since list data is effectively unsigned, perform the final 2's complement
# on the MSbit, and don't force the *set* method to an unsigned value.
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
        return [lrange $inList 4 end]
    }
}

#--------------------------------------------------------------------------
####   int32_bt
#
# Same as *uint32_t* except the list is interpreted as big-endian and the
# value is interpreted as signed.
# Since list data is effectively unsigned, perform the final 2's complement
# on the MSbit, and don't force the *set* method to an unsigned value.
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
        return [lrange $inList 4 end]
    }
}

#--------------------------------------------------------------------------
####   float_t
#
# Four bytes of data interpreted as a single-precision IEEE format
# floating point number.
#
# N.B. that this works only when both sides of the serial interface agree on
# the bit format of a single-precision floating point number.  If they're the
# same processor or processor family it's not an issue; if it's inter-processor
# communication and one of the processors has a different floating-point
# format, much more complex manipulation is needed and a custom class should be
# created for that use.
#
oo::class create ::AutoObject::float_t {
    variable MyValue MyWidget

    constructor {args} { set MyValue 0.0 }
    method get {} { return $MyValue }
    method set {newVal} {
        if [catch {set MyValue [expr {$newVal + 0.0}]} errS] {
            log::error "$newVal is Not a Number!  ($errS)"
            set MyValue "NaN"
        }
    }
    method toString {} {
        if [catch {set outS [format %8f $MyValue]}] {
            log::error "$MyValue is Not a Number!"
        }
        return $outS
    }
    method toList {} {
        # Convert using the native float format.  N.B. this works only
        # when the target & host use the same float format.
        binary scan [binary format f $MyValue] cu* outL
        return $outL
    }
    method fromList {inList} {
        # Convert using the native float format.  N.B. this works only
        # when the target & host use the same float format.
        binary scan [binary format c4 [lrange $inList 0 3]] f value
        set MyValue $value
        return [lrange $inList 4 end]
    }
}

#--------------------------------------------------------------------------
####   time_t
#
# Time is stored internally as a Unix time_t - a 32-bit count of seconds
# since the Unix epoch (Jan 1, 1970).  The set method will accept an integer
# directly, or if passed a non-integer will attempt to parse it using
# clock scan.  If that fails, it allows clock scan to throw the error.
# Since it's stored as a 32-bit int, most methods act as the *uint32_t*
# superclass.
#
# The Constructor can be passed a default time format string to be used when
# stringifying; we also add a method to set the default string later.
# *toString* accepts a format string; if one is not provided it uses the
# default string set earlier.
#
oo::class create ::AutoObject::time_t {
    superclass ::AutoObject::uint32_t
    variable MyFormatStr

    constructor {args} {
        my variable MyValue
        ;# default value for a new time object is "now".
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
    # **time_t.toString**
    #
    # Note that for the *time_t* class, *toString* has an additional optional
    # argument of a format string to be used for this particular call.
    method toString {args} {
        my variable MyValue
        if {$args ne ""} {
            set fmtStr $args
        } else {
            set fmtStr $MyFormatStr
        }
        tailcall clock format $MyValue -format $fmtStr
    }
    # **time_t.setFormat** *newFormatString*
    #
    # Note that the *time_t* class has an additional method: setFormat.
    # This allows the user of the class to change the default format used
    # whenever an object of this class is stringified with the *toString*
    # method.  Also note that *toString* has an additional optional
    # argument of a format string to be used for an individual call.
    method setFormat {newFmtStr} {
        set MyFormatStr $newFmtStr
    }
}

#--------------------------------------------------------------------------
####   string_t
#
# **N.B. This class requires the length of the field to be passed in on creation
# as an additional argument.  If not provided, the constructor will fail.**
#
# The *string_t* autoData type is constrained by the length of its field.  It
# will truncate any attempt to set it to longer to the first N characters that
# will fit into that field length.  If the input is shorter, the string will
# be filled to its field length with NULLs in the line format.
#
# *string_t* expects its string-format data to be ASCII or UTF-8, one byte
# per character.  To store/transfer unicode data, use type *unicode_t*.
oo::class create ::AutoObject::string_t {
    variable MyValue
    variable MyWidget
    variable MyMaxLength

    constructor {args} {
        if {![string is digit -strict [lindex $args 0]]} {
            log::critical "String_t constructor error: string length not\
                    specified as field data value in defining list.\n\
                    Specify field length in the fifth item of the list."
            error "String_t constructor error: string length not\
                    specified as field data value in defining list."
        }
        set MyMaxLength [lindex $args 0]
        set MyValue ""
    }
    method get {} { return $MyValue }
    method set {newVal} {
        set MyValue [string range $newVal 0 [expr {$MyMaxLength - 1}] ]
    }
    method toString {} { return "\"$MyValue\"" }
    method toList {} {
        binary scan $MyValue cu* dataL
        if {[llength $dataL] < $MyMaxLength} {
            lappend dataL {*}[lrepeat [expr {$MyMaxLength - [llength $dataL]}] 0]
        }
        return $dataL
    }
    method fromList {inList} {
        if {$MyMaxLength < [llength $inList]} {
            set dataL [lrange $inList 0 $MyMaxLength-1]
        } else {
            set dataL $inList
        }
        set MyValue [string trimright [binary format c* $dataL] '\0']
        return [lrange $inList $MyMaxLength end]
    }
}

#--------------------------------------------------------------------------
####   unicode_t
#
# **N.B. This class expects the length of the field *IN CHARACTERS* to be
# passed in on creation as an additional argument.  This is different from
# the length in bytes, as characters are expected to take on average 2 bytes
# each.  If not provided, the constructor will fail.  If the length is
# incorrect, the list/byte formats produced will not be the correct length.**
#
# The *unicode_t* autoData type is constrained by the length of its field.  It
# will truncate any attempt to set it to longer to the first N characters that
# will fit into that field length.  If the input is shorter, the string will
# be null terminated and filled with NULLs in the line format.
oo::class create ::AutoObject::unicode_t {
    superclass ::AutoObject::string_t
    variable MyValue MyMaxLength MyWidget

    method toList {} {
        binary scan [encoding convertto unicode $MyValue] cu* dataL
        if {[llength $dataL] < [expr {$MyMaxLength * 2}]} {
            lappend dataL {*}[lrepeat [expr {$MyMaxLength * 2 - [llength $dataL]}] 0]
        }
        return $dataL
    }
    method fromList {inList} {
        if {$MyMaxLength < ([llength $inList] / 2)} {
            set dataL [lrange $inList 0 [expr {($MyMaxLength * 2) - 1}]]
        } else {
            set dataL $inList
        }
        set MyValue [string trimright [encoding convertfrom unicode \
                                       [binary format c* $dataL]] '\0']
        return [lrange $inList [expr {$MyMaxLength * 2}] end]
    }
}

#--------------------------------------------------------------------------
###   enum_mix
#
# This class is a mixin for classes usually based on the *uint8_t* class
# (or *uint16_t* or *uint32_t* if you need large fields for some reason).
# The host class is expected to provide most of the features, including any
# of the length-specific code; the mixin only provides an override for the
# *set* and *toString* methods.
#
# N.B. that the *enum_mix* class is a bit of code clevverness that expects
# to be initialized before use.  The base class only provides the mechanisms;
# initialization provides the lookup table mapping the symbol to the enum
# value.   Without providing the definition of the enum, it's not very useful.
#
# To initialize, immediately after mixing it into the base class, invoke the
# *setEnumDef* proc with the classname and a list consisting of name/value
# pairs.  Objects of the ensuing class will then accept the symbolic names
# of the enum as inputs  to *set*, and will print via *toString* the symbolic
# names.
#
# **N.B. that the *setEnumDef* proc should be invoked on the *class*
# immediately after class definition, not on the resulting objects.
# The extra data is stored in the class object proper, not in the objects
# created by the class.**
#
oo::class create ::AutoObject::enum_mix {
    variable defArray

    method set {newVal} {
        my variable MyValue
        set ns [info object namespace [info object class [self object]]]
        upvar ${ns}::defArray dA
        if {[info exists dA($newVal)]} {
            set MyValue $dA($newVal)
        } else {
            ;# Sometimes input comes in 0x## hex format. Expr it to decimal.
            catch {set newVal [expr $newVal]}
            if {[info exists dA(val-$newVal)]} {
                set MyValue $newVal
            } else {
                log::warn "Tried to set enum [self] to unknown symbol $newVal"
                set MyValue $newVal
            }
        }
    }
    method toString {} {
        my variable MyValue
        set ns [info object namespace [info object class [self object]]]
        upvar ${ns}::defArray dA
        if {[info exists dA(val-$MyValue)]} {
            return $dA(val-$MyValue)
        } else {
            return $MyValue
        }
    }
    # Important note: if using the GUI elements of the system, any *enum_mix*
    # field should specify the *autoCombobox* widget as field 6 of the
    # defining list.
    method createWidget {args} {
        my variable MyWidget
        # N.B. that the *autoCombobox* widget method will be called first in
        # the method chain, and that we only get here by the "next" call.
        if {[winfo class $MyWidget] ne "TCombobox"} {
            puts "I ([self]) am a [winfo class $MyWidget]"
            return
        }
        set ns [info object namespace [info object class [self object]]]
        upvar ${ns}::defArray dA
        set nL [array names dA "val-*"]
        foreach n $nL {lappend enumL $dA($n)}
        $MyWidget configure -values $enumL
        bind $MyWidget <<ComboboxSelected>> [list [self] widgetUpdate]
        $MyWidget set [my toString]
    }
    method widgetUpdate {} {
        my variable MyWidget
        my set [$MyWidget get]
    }
}

# N.B. that the *setEnumDef* proc should be invoked on the **class**
# immediately after class definition, not on the resulting objects.
# The extra data is stored in the class object proper, not in the objects
# created by the class.
proc ::AutoObject::setEnumDef {classname defL} {
    namespace upvar [info object namespace $classname] defArray dA
    array set dA $defL
    foreach {key val} [array get dA] {
        set dA(val-$val) $key
    }
}


#--------------------------------------------------------------------------
###   bitfield_mix
#
# N.B. This class is a mixin for classes based on the *uint8_t* class (or
# *uint16_t* or *uint32_t* if you need large fields for some reason).
# The host class is expected to provide most of the features, including any
# of the length-specific code; the mixin only provides an override for the
# *set*, *get* and *toString* methods.
#
# N.B. the *bitfield_mix* class is a bit of code clevverness that expects to be
# initialized before use.  The base class only provides the mechanisms;
# initialization provides the lookup table mapping the fields to the bits.
# Without providing the definition of the enum, it's not very useful.
#
# To initialize, immediately after mixing it into the base class, invoke the
# *setBitfieldDef* proc with the classname and a list consisting of field
# definition lists, where each field definition list is the name, number of
# bits, and (optional) enum value of the bit combinations (in order 0 -> max).
#
# **N.B. that the *setBitfieldDef* proc should be invoked on the *class*
# immediately after class definition, not on the resulting objects.
# The extra data is stored in the class object proper, not in the objects
# created by the class.**
#
oo::class create ::AutoObject::bitfield_mix {
    variable ns

    method get {args} {
        my variable MyValue ns
        if {![info exists ns]} {
            set ns [info object namespace [info object class [self object]]]
        }
        upvar ${ns}::defArray dA
        if {[llength $args] == 0} {
            return $MyValue
        } else {
            set outL {}
            foreach field $args {
                set val [expr ($MyValue & $dA($field,mask) ) \
                                    >> $dA($field,shift)]
                lappend outL $val
            }
            return $outL
        }
    }
    method set {args} {
        my variable MyValue ns
        if {![info exists ns]} {
            set ns [info object namespace [info object class [self object]]]
        }
        upvar ${ns}::defArray dA
        set len [llength $args]
        # If there's only one value, interpret it as setting the entire value
        if {$len == 1} {
            set MyValue $args
        # If setting individual fields, must be a list of field/value pairs
        } elseif {$len % 2 == 0} {
            foreach {key val} $args {
                # If there is an enum and the input is a known symbol,
                # use its value
                if {[info exists dA($key,enumL)] && \
                        ($val in $dA($key,enumL))} {
                    set val [lsearch $dA($key,enumL) $val]
                }
                # Shift up the field value, mask & combine with the rest.
                set MyValue [expr {($MyValue & ~$dA($key,mask)) | \
                                    (($val << $dA($key,shift)) & \
                                    $dA($key,mask))}]
            }
        } else {
            error "Odd number of items in key/value list: \
                        [llength $args] items in $args"
        }
    }
    method toString {} {
        my variable MyValue
        if {![info exists ns]} {
            set ns [info object namespace [info object class [self object]]]
        }
        upvar ${ns}::defArray dA
        set outS ""
        set newline ""
        # We print field names indented up to the data side of the format,
        # so compute where that is.
        set nameSize [expr [string length [lindex $dA(nameL) 0]] + 44]
        set outS [format "%s  Decoded to:\n" [next]]
        foreach name $dA(nameL) {
            set val [expr ($MyValue & $dA($name,mask)) \
                                    >> $dA($name,shift)]
            # If there's an enum, print the symbol if it exists.
            # Otherwise, print it in binary.
            if {[info exists dA($name,enumL)] && \
                    $val < [llength $dA($name,enumL)]} {
                set valS [lindex $dA($name,enumL) $val]
            } else {
                set size $dA($name,size)
                set valS [format "b'%0${size}b" $val]
            }
            append outS [format "%${nameSize}s - %s\n" $name $valS]
        }
        # trim to display multiline output properly in autoObject output
        set outS [string trimright $outS "\n"]
        return $outS
    }
;# @@@ TODO %%%
;# Special widget not yet defined; commented out until working.
;#    # N.B. that the base widget method will be called first in the
;#    # method chain, and that we only get here by the "next" call.
;#    method createWidget {args} {
;#        my variable MyWidget
;#        set ns [info object namespace [info object class [self object]]]
;#        upvar ${ns}::defArray dA
;#        # Get rid of the old widget, replacing by the collection of
;#        # per-bitfield widgets
;#        set wname $MyWidget
;#        destroy $MyWidget
;#
;#        foreach name $dA(nameL) {
;#        }
;#
;#    }
    method widgetUpdate {} {
        my variable MyWidget
        my set [$MyWidget get]
    }
}

# N.B. that the *setBitfieldDef* proc should be invoked on the **class**
# immediately after class definition, not on the resulting objects.
# The extra data is stored in the class object proper, not in the objects
# created by the class.
proc ::AutoObject::setBitfieldDef {classname defL} {
    set [info object namespace $classname]::ns [info object namespace $classname]
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

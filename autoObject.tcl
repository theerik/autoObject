#!/bin/sh
# The next line is executed by /bin/sh, but not tcl \
exec tclsh "$0" ${1+"$@"}

#--------------------------------------------------------------------------
#
# FILENAME:    autoObject.tcl
#
# AUTHOR:      theerik@github
#
# DESCRIPTION:  AutoObject is a base class used to create auto-assembling
#               objects using a descriptor array.  The key feature is that
#               objects can be serialized and deserialized to/from byte
#               array format, allowing them to be passed to or received
#               from any interface that supports byte array/serial formats.
#               Past applications include serialized structures for
#               COM interfaces, message formats for serial communication,
#               and parsing of memory blocks rerieved from embedded targets.
#
#--------------------------------------------------------------------------
#
# Copyright 2015, Erik N. Johnson
#
#--------------------------------------------------------------------------

package provide autoObject 0.1
source [file join [file dirname [info script]] autoObjectData.tcl]

if {[info procs vlog] eq {}} {
    proc ::vlog {msg} {
        if {[info exists ::verbose] && $::verbose} {
            puts $msg
        }
    }
}

#--------------------------------------------------------------------------
#  autoObject base class
#
# Uses the defining array to set up field keys, to mixin the types of the
#   fields and initialize them to default values.
#
# The field types must support canonical methods to determine how to parse
#   or generate wire format, and to output human-readable values for logging
#   and debug.
oo::class create autoObject {
    variable FieldSize FieldOffset DataArray NameL
    variable BlockSize Variable_size Initialized

    #--------------------------------------------------------------------------
    # autoObject constructor
    #
    # The constructor takes as input an array defining the object to be created.
    # The defining array has the field names as keys, with each key pointing to
    # a list of 5 elements:
    #   {   field_offset    # must start at 0, incr by field_size, leave no gaps
    #       field_size      # max size of field in bytes in serialized stream
    #       field_type      # name of the data type.  Must support methods used
    #                       # by autoType, can have others.
    #       init_value      # value to initialize field data to.  can be empty {}
    #       field_data      # Passed to constructor when creating the object of
    #                       # type <field_type>, not used or examined by
    #                       # autoObject.  Can be empty {}.
    #   }
    # There is one other valid key, "variable_length_object", which can be true
    # or false (or not defined).  If defined true, input checking for too-small
    # input is disabled, and the last field is treated as variable in size.
    #
    constructor { dbName args } {
        # As we read the field list to initialize the fields, parse the
        # sizes and offsets to validate the input.  There should be no
        # missing bytes in the structure.
        upvar $dbName definingDb
        set currOffset 0
        set Variable_size false
        set NameL [lsort -command "my showQuerySort definingDb" \
                   [array names definingDb]]
        vlog "class list: [info class instances oo::class ::AutoData::*]"
        foreach field $NameL {
            if {$field eq "variable_length_object" && $definingDb($field)} {
            vlog "$field: $definingDb($field)"
                set Variable_size true
                continue
            }
            set fieldList $definingDb($field)
            vlog "$field: $fieldList"
            set FieldOffset($field) [lindex $fieldList 0]
            if {$currOffset != $FieldOffset($field)} {
                error "Invalid defining array $dbName: at offset\
                       $FieldOffset($field), expected $currOffset"
            }
            set FieldSize($field) [lindex $fieldList 1]
            set currOffset [expr {$currOffset + $FieldSize($field)}]

            # Find the data type corresponding to the name.
            set tname "[lindex $fieldList 2]"
            set isarray [regexp {(.+)\[([0-9]+)\]} $tname -> basename arrcount]
            if $isarray {
                set tname $basename
            }
            if {[lsearch [info class instances oo::class ::AutoData::*] \
                                                "::AutoData::Auto_$tname"] != -1} {
                # Found as a basic Auto type
                set tname "::AutoData::Auto_$tname"
            } elseif {[lsearch [info class instances oo::class ::AutoData::*] \
                       "::AutoData::$tname"] != -1} {
                # Found as a custom type in the correct namespace
                set tname "::AutoData::$tname"
            } elseif {[lsearch [info class instances oo::class] \
                       $tname] != -1} {
                # Found something poorly set up; nothing else to do here
                # but either keep going or die in error
            } else {
                error "Unknown type requested: $tname"
            }
            set initData [lindex $fieldList 3]
            set typeData [lindex $fieldList 4]
            if $isarray {
                # validate size is an integral number of bytes per entry
                set bytesPerObj [expr {int($FieldSize($field) / $arrcount)}]
                if {$arrcount * $bytesPerObj != $FieldSize($field)} {
                    error "Size not an integer multiple of array count.\n\
                           Array count: $arrcount, size: $FieldSize($field)"
                }
                if {[llength $initData] != $arrcount} {
                    # We aren't given an exact list of initializer data, so
                    # assume data is for one element.
                    set initData [lrepeat $arrcount $initData]
                }
                for {set idx 0} {$idx < $arrcount} {incr idx} {
                    if [catch {set obj [$tname new $typeData]}] {
                        error "Failed to create new object of type\
                               $tname for field $field element $idx."
                    }
                    $obj set [lindex $initData $idx]
                    lappend DataArray($field) $obj
                }
            } else {
                if [catch {set DataArray($field) [$tname new $typeData]}] {
                    error "Failed to create new object of type\
                           $tname for field $field."
                }
                $DataArray($field) set $initData
            }
        }
        set BlockSize $currOffset
        set Initialized false
    }

    #--------------------------------------------------------------------------
    # autoObject.get
    #
    # Simple getter: accepts a list of keys, and returns a list of values for
    # each key provided.  If no key is provided, returns the entire data array.
    # Alerts on unknown keys.
    method get {args} {
        set outL {}
        if {$args == {}} {
            foreach name $NameL {
                lappend outL $name $DataArray($name)
            }
            return $outL
        }
        if {[llength $args] == 1} {
            if {[info exists DataArray($args)]} {
                return $DataArray($args)
            } else {
                alert "Requesting non-existant field in [info object class \
                        [self object]] [self object]: $args"
            }
        }
        foreach {key} $args {
            if {[info exists DataArray($key)]} {
                lappend outL $DataArray($key)]
            } else {
                alert "Requesting non-existant field in [info object class \
                        [self object]] [self object]: $key"
            }
        }
        return $outL
    }


    #--------------------------------------------------------------------------
    # autoObject.set
    #
    # Simple mutator: accepts a list of key/value pairs, and for each key sets
    # the associated value to the supplied value.
    # Warns on but does not reject unknown keys.
    method set {args} {
        if {[llength $args] %2 == 1} {
            error "Odd number of arguments to set - requires key/value pairs only."
        }
        foreach {key val} $args {
            if {[lsearch $NameL $key] == -1} {
                log "Warning: Setting non-standard field in [info object class \
                        [self object]] [self object]: $key <- $val" true
            }
            DataArray($key) set $val
        }
    }

    #--------------------------------------------------------------------------
    # autoObject.fromList(inputList)
    #
    # Setter from byte-list format, as usually supplied by a decoded message.
    # Accepts the byte list, parses it as defined in the associated defining
    # array, and stores it in the object's data array.
    method fromList {dataL} {
        # Check that input is correct size for object
        if {$BlockSize != [llength $dataL]} {
            set dl [llength $dataL]
            if { $dl > $BlockSize } {
                # in all cases, too large is an error
                alert "Input for [info object class [self object]] is too\
                        large!  Length: $dl; should be <= $BlockSize."
                vlog "Data is: $dataL"
            } elseif { $Variable_size } {
                # Allowed to be smaller but not larger
                log "Input for [info object class [self object]] is size $dl\
                        bytes (max allowed is $BlockSize)."
                if {$dl == 0} {
                    # Special case - clear out the existing data, because we won't loop
                    # past the end of the 0 byte input block. Set the values as on init.
                    foreach {field fieldList} [array get db] {
                        set DataArray($field) [lindex [lindex $fieldList 3] 0]
                    }
                }
            } else {
                # block is smaller and is not variable-length
                alert "Input for [info object class [self object]] has an\
                        incorrect length: $dl; should be $BlockSize."
                vlog "Data is: $dataL"
            }
        }

        foreach name $NameL {
            set offset $FieldOffset($name)
            set size $FieldSize($name)
            set byteL [lrange $dataL $offset [expr {$offset + $size - 1}]]

            vlog "Getting $name value from dataL($offset -\
                    [expr {$offset + $size - 1}]): $byteL"
            if {[llength $DataArray($name)] == 1} {
                $DataArray($name) fromList $byteL
                vlog "$name set to [$DataArray($name) get]"
            } else {
                set numObj [llength $DataArray($name)]
                set bytesPerObj [expr {$size / $numObj}]
                set offset 0
                foreach obj $DataArray($name) {
                    set start $offset
                    incr offset $bytesPerObj
                    set end [expr {$offset - 1}]
                    set subL [lrange $byteL $start $end]
                    $obj fromList $subL
                }
            }
        }
        set Initialized true
    }

    #--------------------------------------------------------------------------
    # autoObject.toList(inputList)
    #
    # Getter to byte-list format, as required to send to the target.
    # Pulls the fields in the order defined by the datablock array, converts the
    # complex data to a combined byte list, and returns the list.
    method toList {} {
        set dbData {}
        # Iterate over the ordered list of field names
        foreach name $NameL {
            vlog "Converting $name..."
            # List should have been the right size coming in...
            set offset $FieldOffset($name)
            if {[llength $dbData] != $offset} {
                error "Data list incorrect size starting $name.  Expected\
                       $offset bytes, got [llength $dbData] ($dbData)."
            }
            if {[llength $DataArray($name)] == 1} {
                set dataL [$DataArray($name) toList]
            } else {
                set dataL {}
                foreach obj $DataArray($name) {
                    lappend dataL {*}[$obj toList]
                }
            }
            # Field object should generate correct list length.
            set size $FieldSize($name)
            if {[llength $dataL] != $size} {
                error "Data object $name generated wrong size list. \
                       Expected $size bytes, got [llength $dataL] ($dataL)."
            }
            lappend dbData {*}$dataL
            unset dataL
        }

        # Convert to list of non-negative byte values (range 0-255)
        foreach b $dbData {
            lappend outL [expr $b % 256]
        }
        return $outL
    }

    #--------------------------------------------------------------------------
    # autoObject.toString
    #
    # Getter to screen format.  For each field, retrieves the value and appends
    # it to the output string in the style defined by the type in the field
    # array.  Displays fields not defined in the defining array at the end,
    # marked as special.
    #
    # This can be overridden by derived classes to create a different default
    # format, but has a nominal implementation in place.
    method toString { {keysL {}} } {
        vlog ""
        vlog "    [ info object class [self object] ] [self object]:"
        set outL {}

        foreach name $NameL {
            set size $FieldSize($name)
            set offset $FieldOffset($name)

            # Set value with string from field objects
            if {[llength $DataArray($name)] > 1} {
                set outStr ""
                foreach obj $DataArray($name) {
                    append outStr "[$obj toString] "
                }
                set outStr [string trimright $outStr " "]
            } else {
                set outStr [$DataArray($name) toString]
            }

            lappend outL [format "    ...%-35s: %s" $name $outStr]
        }

        # Be sure to document extra fields in the data dict
        foreach {name value} [array get DataArray] {
            if {$name ni $NameL} {
                lappend lines [format "    ...%-35s: %s" $name $value]
            }
        }
        if {[info exists lines]} {
            lappend outL ""
            lappend outL "Extra fields in datablock:"
            foreach line $lines {
                lappend outL $line
            }
            unset lines
        }
        return [join $outL "\n"]
    }

    #--------------------------------------------------------------------------
    # autoObject.fromByteArray
    #
    # From wire format or COM interface.  Converts from binary and calls fromList.
    method fromByteArray {byteArray} {
        binary scan $byteArray "c*" byteList
        foreach b $byteList {
            lappend posL [expr $b % 256]
        }
        my fromList $posL
    }

    #--------------------------------------------------------------------------
    # autoObject.toByteArray
    #
    # To wire format or COM interface.  Wraps toList and converts to binary.
    method toByteArray {} {
        set byteList [my toList]
        set byteArray [binary format "c*" $byteList]
        return $byteArray
    }

    #--------------------------------------------------------------------------
    # autoObject.showQuerySort
    #
    # helper proc used to sort name list by field offset
    method showQuerySort {arrayname a b} {
        upvar $arrayname array
        if {[lindex $array($a) 0] == [lindex $array($b) 0]} {
            return 0
        } elseif {[lindex $array($a) 0] < [lindex $array($b) 0]} {
            return -1
        } else {
            return 1
        }
    }
}

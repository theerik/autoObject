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
#               objects using runtime descriptors.  The key feature is that
#               objects can be serialized and deserialized to/from byte
#               array format, allowing them to be passed to or received
#               from any interface that supports byte array/serial formats.
#               Past applications include serialized structures for
#               COM interfaces, message formats for serial communication,
#               and parsing of memory blocks rerieved from embedded targets.
#
#--------------------------------------------------------------------------
#
# Copyright 2015-16, Erik N. Johnson
#
#--------------------------------------------------------------------------

package require TclOO
package require logger

if {![namespace exists ::AutoObject] } {
    namespace eval ::AutoObject {
        variable version 0.6
        logger::init ::autoObject
        logger::import -all -namespace ::autoObject::log ::autoObject
        ::autoObject::log::setlevel warn
    }
    source [file join [file dirname [info script]] autoObjectWidgets.tcl]
    source [file join [file dirname [info script]] autoObjectData.tcl]

#--------------------------------------------------------------------------
#  autoObject base class
#
# Uses the defining list to set up field keys, to create the field objects
#   by type, and to initialize them to default values.
#
# The field object types must support canonical methods to determine how to
#   parse or generate wire format, to programmatically set or get values,
#   and to output human-readable values for logging and debug.
oo::class create ::autoObject {
    variable BlockSize
    variable DataArray
    variable FieldInfo
    variable Initialized
    variable NameL
    variable Variable_size

    #--------------------------------------------------------------------------
    # autoObject constructor
    #
    # The constructor takes as input a list defining the object to be created.
    # The defining list has the form of key/value pairs, with field names
    # as keys paired with a nested list of up to 6 elements, the first 3 
    # of which are mandatory:
    #   {   field_offset    # must start at 0, incr by field_size, leave no gaps
    #       field_size      # max size of field in bytes in serialized stream
    #       field_type      # name of the data type.  Must support methods used
    #                       # by autoObject types, can have others.
    #       init_value      # value to initialize field data to. Can be empty {}
    #       field_data      # Passed to constructor when creating the object of
    #                       # type <field_type>, not used or examined by
    #                       # autoObject.  Can be empty {}.
    #       widget_name     # name of an autoWidget class to use to display
    #                       # the data in GUIs.  Can be empty, in which case
    #                       # the autoWidget "autoEntry" will be used.
    #   }
    # If fewer than 6 elements are provided, the remainder will be filled
    # with default values as noted, usually the empty list {}.
    #
    # There is one special valid key name, "variable_length_object", whose
    # value is a single number defining the minimum size of the object.
    # If the value == 0, it is treated as disabling the special handling;
    # otherwise, too-small input is changed to a minimum of $value, and fields
    # past that size are permitted to be variable in size.
    #
    constructor { defineL } {
        logger::import -all -force -namespace log ::autoObject
        
#log::setlevel debug
        array set definingArr $defineL
        set currOffset 0
        set Variable_size 0
        set NameL [lsort -command "my ShowQuerySort definingArr" \
                   [array names definingArr]]

        # As we read the field list to initialize the fields, parse the
        # sizes and offsets to validate the input.  There should be no
        # missing bytes in the structure.
        foreach field $NameL {
            if {$field eq "variable_length_object"} {
                log::debug "$field: $definingArr($field)"
                set Variable_size $definingArr($field)
                # Take this special token out of the NameL - we don't want to
                # set, get, or process it like the others.
                set idx [lsearch $NameL "variable_length_object"]
                set NameL [lreplace $NameL $idx $idx]
                continue
            }
            set fieldList $definingArr($field)
            log::debug "$field: $fieldList"
            set FieldInfo($field,offset) [lindex $fieldList 0]
            if {$currOffset != $FieldInfo($field,offset)} {
                error "Invalid defining list: at offset\
                       $FieldInfo($field,offset), expected $currOffset"
            }
            set FieldInfo($field,size) [lindex $fieldList 1]
            set currOffset [expr {$currOffset + $FieldInfo($field,size)}]

            # Find the data type corresponding to the name.
            set tname "[lindex $fieldList 2]"
            set isarray [regexp {(.+)\[([0-9]+)\]} $tname -> basename arrcount]
            if $isarray {
                set tname $basename
            } else {
                set arrcount 0
            }
            if {"::AutoObject::$tname" in \
                    [info class instances oo::class ::AutoObject::*]} {
                # Found as a type declared in the appropriate namespace
                set tname "::AutoObject::$tname"
            } elseif {[lsearch [info class instances oo::class] "*$tname"] != -1} {
                # Found something not in the right namespace; we either try it
                # or die in error and we may as well keep going and try it.
                log::debug "class list: [info class instances oo::class ::AutoObject::*]"
                set msg "No $tname in expected namespace.  Found %s and will try it."
                set tname [lindex [info class instances oo::class] \
                           [lsearch [info class instances oo::class] "*$tname"]]
                log::info [format $msg $tname]
            } else {
                log::error "Unknown type requested: $tname"
                log::error "List of autoObject classes: [info class instances oo::class ::AutoObject::*]"
                log::error "List of classes: [info class instances oo::class]"
                error "Unknown type requested: $tname"
            }
            set FieldInfo($field,tname) $tname
            set FieldInfo($field,arrcnt) $arrcount
            if {[llength $fieldList] > 3} {
                set initData [lindex $fieldList 3]
            } else {
                set initData {}
            }
            if {[llength $fieldList] > 4} {
                set typeData [lindex $fieldList 4]
            } else {
                set typeData {}
            }
            if {([llength $fieldList] > 5) && ([lindex $fieldList 5] ne {})} {
                set wname [lindex $fieldList 5]
                if {"::AutoObject::$wname" in \
                            [info class instances oo::class ::AutoObject::*]} {
                    # Found as a type declared in the appropriate namespace
                    set widgetName "::AutoObject::$wname"
                } elseif {[lsearch [info class instances oo::class] "*$wname"] != -1} {
                    # Found something not in the right namespace; we either try it
                    # or die in error and we may as well keep going and try it.
                    log::debug "class list: [info class instances oo::class ::AutoObject::*]"
                    set msg "No $wname in expected namespace.  Found %s and will try it."
                    set widgetName [lindex [info class instances oo::class] \
                               [lsearch [info class instances oo::class] "*$wname"]]
                    log::info [format $msg $widgetName]
                } else {
                    log::error "Unknown type requested: $wname"
                    log::error "List of autoObject classes: [info class instances oo::class ::AutoObject::*]"
                    log::error "List of classes: [info class instances oo::class]"
                    error "Unknown type requested: $wname"
                }
            } else {
                set widgetName ::AutoObject::autoEntry
            }
            if {$isarray} {
                # validate size is an integral number of bytes per entry
                set bytesPerObj [expr {int($FieldInfo($field,size) / $arrcount)}]
                if {$arrcount * $bytesPerObj != $FieldInfo($field,size)} {
                    error "Size not an integer multiple of array count.\n\
                           Array count: $arrcount, size: $FieldInfo($field,size)"
                }
                if {[llength $initData] != $arrcount} {
                    # We aren't given an exact list of initializer data, so
                    # assume data is for one element.
                    set initData [lrepeat $arrcount $initData]
                }
                set DataArray($field) {}
                for {set idx 0} {$idx < $arrcount} {incr idx} {
                    if [catch {set obj [$tname new $typeData]}] {
                        error "Failed to create new object of type\
                               $tname for field $field element $idx:\
                               $::errorInfo"
                    }
                    $obj set [lindex $initData $idx]
                    # Mix in the GUI class
                    oo::objdefine $obj [list mixin $widgetName]
                    lappend DataArray($field) $obj
                }
                # Forward the field name as a method name to a special
                # method that iterates across the list of items in the field,
                # runs whatever method of the item the user wants on each one,
                # and collects the results in a list that is returned.
                oo::objdefine [self] forward $field my IterField $field
            } else {
                if [catch {set DataArray($field) [$tname new $typeData]}] {
                    error "Failed to create new object of type\
                           $tname for field $field: $::errorInfo"
                }
                $DataArray($field) set $initData
                # Mix in the GUI class
                oo::objdefine $DataArray($field) [list mixin $widgetName]
                # Forward the field name as a method name to the object that
                # the field is composed of.
                oo::objdefine [self] forward $field $DataArray($field) 
            }
            oo::objdefine [self] export $field
        }
        set BlockSize $currOffset
        set Initialized false
    }
    method isInitialized {} {return $Initialized}

    #--------------------------------------------------------------------------
    # autoObject.get
    #
    # Simple getter: accepts a list of keys, and returns a list of values for
    # each key provided.  If no key is provided, returns the entire data array.
    # Alerts on unknown keys.
    method get {args} {
        set outL {}
        if {$args == {}} {
            foreach key $NameL {
                if {[llength $DataArray($key)] > 1} {
                    set tempL {}
                    foreach obj $DataArray($key) {
                        lappend tempL [$obj get]
                    }
                    lappend outL $key $tempL
                } else {
                    lappend outL $key [$DataArray($key) get]
                }
            }
        } elseif {[llength $args] == 1} {
            if {$args in $NameL} {
                if {[llength $DataArray($args)] > 1} {
                    set tempL {}
                    foreach obj $DataArray($args) {
                        lappend tempL [$obj get]
                    }
                    return $tempL
                } else {
                    return [$DataArray($args) get]
                }
            } elseif {[info exists DataArray($args)]} {
                return $DataArray($args)
            } else {
                my variable $args
                if {[info exists $args]} {
                    return [set $args]
                } else {
                    log::error "Requesting non-existant field in [info object \
                            class [self object]] [self object]: \"$args\" not\
                            in \"[array names DataArray]\""
                }
            }
        } else {
            foreach {key} $args {
                if {$key in $NameL} {
                    if {[llength $DataArray($key)] > 1} {
                        set tempL {}
                        foreach obj $DataArray($key) {
                            lappend tempL [$obj get]
                        }
                        lappend outL $tempL
                    } else {
                        lappend outL [$DataArray($key) get]
                    }
                } elseif {[info exists DataArray($key)]} {
                    lappend outL $DataArray($key)
                } else {
                    log::error "Requesting non-existant field in [info object \
                                class [self object]] [self object]: \"$key\" \
                                not in \"[array names DataArray]\""
                }
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
            log::debug "$key: $val"
            if {$key ni $NameL} {
                log::warn "Warning: trying to set non-standard field in [info object class \
                        [self object]] [self object]: $key <- $val" true
                set $DataArray($key) $val
            }
            if {$FieldInfo($key,arrcnt) != 0} {
                if {$Variable_size == 0} {
                    # Fixed length object
                    if {([llength $DataArray($key)] != [llength $val]) } {
                        set errmsg "incorrect number of items to set in $key: \
                                    using [llength $val] arguments to set\
                                    [llength $DataArray($key)] objects."
                        log::error $errmsg
                        error $errmsg
                    } else {
                        lmap obj $DataArray($key) item $val { $obj set $item }
                    }
                } else {
                    # Variable length object - reject if the data is too long,
                    # or so small that it's not big enough to fill the minimum.
                    set inlen [llength $val]
                    set offset $FieldInfo($key,offset)
                    if {($Variable_size > ($offset + $inlen)) ||
                            ($FieldInfo($key,arrcnt) < $inlen)} {
                        set errmsg "Incorrect number of items to set in $key: \
                                    using $inlen arguments to set\
                                    up to [llength $DataArray($key)] objects."
                        log::error $errmsg
                        log::error "Variable_size: $Variable_size, arrcnt: $FieldInfo($key,arrcnt)"
                        error $errmsg
                    } else {
                        # Set the objects to the new values.  If we have
                        # too many objects, unset the unused ones.  If we
                        # have too few, create new ones.
                        if {[llength $DataArray($key)] > $inlen} {
                            foreach obj [lrange $DataArray($key) $inlen end] {
                                $obj destroy 
                            }
                            set DataArray($key) [lrange $DataArray($key) 0 $inlen-1]
                        } elseif {[llength $DataArray($key)] < $inlen} {
                            for {set i [llength $DataArray($key)]} {$i < $inlen} {incr i} {
                                lappend DataArray($key) [$FieldInfo($key,tname) new {}]
                            }
                        }
                        lmap obj $DataArray($key) item $val { $obj set $item }
                    }
                }
            } else {
                $DataArray($key) set $val
            }
        }
    }

    #--------------------------------------------------------------------------
    # autoObject.follow
    #
    # Returns a fully qualified path to the value of the data object;
    # normally used by GUIs to use a field as a textvariable.  If the data
    # is a list of object, returns a list of FQPs, one per object.
    method follow {key} {
        if {$FieldInfo($key,arrcnt) == 0} {
            return [info object namespace $DataArray($key)]::MyValue
        } else {
            set tempL {}
            foreach obj $DataArray($key) {
                lappend tempL [info object namespace $obj]::MyValue]
            }
            return $tempL
        }
    }

    #--------------------------------------------------------------------------
    # autoObject.createWidget
    #
    # Returns a Tk name of a frame that encloses a grid of name/value paired
    # widgets.  Names are labels; values are whatever widget the value object
    # has mixed in that responds to the createWidget method call.  
    method createWidget {wname} {
        my variable MyWidget
        # Create encapsulating frame
        ttk::frame $wname
        set row 1
        # @@@ TODO %%% llength NameL is not really the right number for
        # number of rows - doesn't take into account dropped reserved
        # fields or arrays/bitfields that take multiple rows.  Figure it
        # out later.
        if {[llength $NameL] > 20} {
            set splitRow [expr {([llength $NameL] + 1)/ 2}]
        } else {
            # Even if we think we don't need to split, split at 40 to
            # keep at the size of the monitor :-P
            set splitRow 40
        }
        set colNum 0
        foreach key $NameL {
            set winName [string tolower $key]
            if {[llength $DataArray($key)] == 1} {
                grid [ttk::label $wname.l$winName -text $key] -column $colNum \
                        -row $row -sticky nsew
                set MyWidget [$DataArray($key) createWidget $wname.$winName]
                if {$MyWidget eq ""} { continue }
                grid $MyWidget -column [expr $colNum + 1] -row $row -sticky nsew
                incr row
                set FieldInfo($key,widget) $MyWidget
            } else {
                grid [ttk::label $wname.l$winName -text $key] -column $colNum \
                        -row $row -sticky nsew
                set widL {}
                foreach obj $DataArray($key) {
                    set wnum [llength $widL]
                    set MyWidget [$obj createWidget $wname.$winName$wnum]
                    # Special support for reserved fields - if no widget
                    # is returned, don't try to grid it or add rows.
                    if {$MyWidget eq ""} { continue }

                    lappend widL $MyWidget
                    grid $MyWidget -column [expr $colNum + 1] -row $row -padx 4 -sticky nsew
                    incr row
                }
                set FieldInfo($key,widget) $widL
            }
            if {$row > $splitRow} {
                set row 1
                incr colNum 2
            }
        }
        grid columnconfigure $wname 0 -weight 1
        grid columnconfigure $wname 1 -weight 4
        return $wname
    }

    #--------------------------------------------------------------------------
    # autoObject.fromList(inputList)
    #
    # Setter from byte-list format, as usually supplied by a decoded message.
    # Accepts the byte list, parses it as defined in the associated defining
    # array, and stores it in the object's data array.
    method fromList {dataL} {
#log::setlevel debug
        set dl [llength $dataL]
        # Check that input is correct size for object
        if {$BlockSize != [llength $dataL]} {
            if { $dl > $BlockSize } {
                # in all cases, too large is an error
                log::error "Input for [info object class [self object]] is too\
                        large!  Length: $dl; should be <= $BlockSize."
            } elseif { $Variable_size == 0 } {
                # block is smaller and is not variable-length
                log::error "Input for [info object class [self object]] has an\
                        incorrect length: $dl; should be $BlockSize."
            } else {
                # Variable is allowed to be smaller but not larger
                log::info "Input for [info object class [self object]] is size\
                        $dl bytes (max allowed is $BlockSize, min is\
                        $Variable_size)."
                if {$dl == 0} {
                    # Special case - clear out the existing data, because we
                    # won't loop past the end of the 0 byte input block.
                    foreach field $NameL {
                        my set $field 0
                    }
                    return
                }
            }
            log::debug "Data is: $dataL"
        }

        #Input is acceptable.  Process it in field order.
        foreach name $NameL {
            set offset $FieldInfo($name,offset)
            set size $FieldInfo($name,size)
            if {$offset >= $dl} {
                # Once we're past the end of the list, stop processing.
                break
            }
            set byteL [lrange $dataL $offset [expr {$offset + $size - 1}]]

            log::debug "Getting $name value from dataL($offset -\
                    [expr {$offset + $size - 1}]): $byteL"
            if {[llength $DataArray($name)] == 1} {
                $DataArray($name) fromList $byteL
                log::debug "$name set to [$DataArray($name) get]"
            } else {
                set bytesPerObj [expr {$size / $FieldInfo($name,arrcnt)}]
                set offset 0
                if {$Variable_size != 0} {
                    set numIn [expr {[llength $byteL] / $bytesPerObj}]
                    # If variable size, set the number of objects to match 
                    # the input data.  If we have too many objects, unset the
                    # unused ones.  If we have too few, create new ones.
                    if {[llength $DataArray($name)] > $numIn} {
                        foreach obj [lrange $DataArray($name) $numIn end] {
                            $obj destroy 
                        }
                        set DataArray($name) [lrange $DataArray($name) 0 $numIn-1]
                    } elseif {[llength $DataArray($name)] < $numIn} {
                        lappend DataArray($name) [lrepeat [expr {$numIn - \
                                        [llength $DataArray($name)]}] \
                                        [$FieldInfo($name,tname) new {}]]
                    }
                }
                foreach obj $DataArray($name) {
                    set start $offset
                    incr offset $bytesPerObj
                    set end [expr {$offset - 1}]
                    set subL [lrange $byteL $start $end]
                    $obj fromList $subL
                }
            }
        }
#log::setlevel warn
        set Initialized true
    }

    #--------------------------------------------------------------------------
    # autoObject.toList(inputList)
    #
    # Getter to byte-list format, as required to send to the target.
    # Pulls the fields in the order defined by the datablock array, converts the
    # complex data to a combined byte list, and returns the list.
    method toList {} {
        set outL {}
        # Iterate over the ordered list of field names
        foreach name $NameL {
            log::debug "Converting $name..."
            # List should have been the right size coming in...
            set offset $FieldInfo($name,offset)
            if {[llength $outL] != $offset && $Variable_size == 0} {
                error "Data list incorrect size starting $name.  Expected\
                       $offset bytes, got [llength $outL] ($outL)."
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
            set size $FieldInfo($name,size)
            if {[llength $dataL] != $size && $Variable_size == 0} {
                set errMsg "Data object $name generated wrong size list. \
                       Expected $size bytes, got [llength $dataL] ($dataL)."
                error $errMsg
            }
            lappend outL {*}$dataL
            unset dataL
        }

        # Convert to list of non-negative byte values (range 0-255)
        set retL {}
        foreach b $outL {
            lappend retL [expr {$b & 0xff}]
        }
        return $retL
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
        log::debug ""
        log::debug "    [ info object class [self object] ] [self object]:"
        set outL {}
        if {[llength $keysL] == 0} {
            set keysL $NameL
        }
#log::setlevel debug
        foreach name $keysL {
            set size $FieldInfo($name,size)
            set offset $FieldInfo($name,offset)
            log::debug "$name: $size bytes @ $offset bytes"

            # Set value with string from field objects
            if {[llength $DataArray($name)] > 1} {
                set outStr ""
                set cnt -1
                foreach obj $DataArray($name) {
                    if {[incr cnt] == 8} {
                        append outStr "\n"
                        append outStr [string repeat " " 44]
                        set cnt 0
                    }
                    append outStr "[$obj toString] "
                }
                set outStr [string trimright $outStr " "]
            } elseif {[llength $DataArray($name)] == 0}  {
                set outstr "No Data"
            } else {
                set outStr [$DataArray($name) toString]
            }

            lappend outL [format "       %35s: %s" $name $outStr]
        }

        # Be sure to document extra fields in the data dict
        foreach {name value} [array get DataArray] {
            if {$name ni $NameL} {
                lappend lines [format "       %35s: %s" $name $value]
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
        binary scan $byteArray "cu*" byteList
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
    # autoObject.ShowQuerySort
    #
    # helper proc used to sort name list by field offset
    method ShowQuerySort {arrayname a b} {
        if {$a eq "variable_length_object"} {return -1}
        if {$b eq "variable_length_object"} {return 1}
        upvar $arrayname array
        if {[lindex $array($a) 0] == [lindex $array($b) 0]} {
            return 0
        } elseif {[lindex $array($a) 0] < [lindex $array($b) 0]} {
            return -1
        } else {
            return 1
        }
    }
    
    #--------------------------------------------------------------------------
    # autoObject.IterField
    #
    # helper proc used to forward commands to an autoData field if the field
    # is a list/array of objects.  Iterates across all the objects in the
    # list of that field, runs the desired command on each one, collects the
    # return values in a list, and returns that list.  
    method IterField {fieldName args} {
        foreach obj $DataArray($fieldName) {
            lappend outL [$obj {*}$args]
        }
        return $outL
    }
}

}
package provide autoObject $::AutoObject::version

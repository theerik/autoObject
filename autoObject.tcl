#--------------------------------------------------------------------------
#
# FILENAME:    autoObject.tcl
#
# AUTHOR:      theerik@github
#
# DESCRIPTION:
#               AutoObject is a base class used to create auto-assembling
#               objects using runtime descriptors.  The key feature is that
#               objects can be serialized and deserialized to/from byte
#               array format, allowing them to be passed to or received
#               from any interface that supports byte array/serial formats.
#               Past applications include converting structured data to/from
#               byte arrays for COM interfaces to other languages, message
#               formats for serial communication, and parsing of memory
#               blocks retrieved from embedded targets.
#
###########################################################################
#
# Copyright 2015-17, Erik N. Johnson
#
###########################################################################
#
# This package documentation is auto-generated with
# Pycco: <https://pycco-docs.github.io/pycco/>
#
# Use "pycco filename" to re-generate HTML documentation in ./docs .
#

package require TclOO
package require logger

if {![namespace exists ::AutoObject] } {
    namespace eval ::AutoObject {
        variable version 0.7
        logger::init ::autoObject
        logger::import -all -namespace ::autoObject::log ::autoObject
        ::autoObject::log::setlevel warn
    }
source [file join [file dirname [info script]] autoObjectWidgets.tcl]
source [file join [file dirname [info script]] autoObjectData.tcl]

#--------------------------------------------------------------------------
##  autoObject base class
#
# Creates objects that use a defining list to: set up field keys that reference
#   fields, create the objects populating those fields by type defined in
#   the defining list, and initialize the field objects to default values.
#
# The field object types must support canonical methods to determine how to
#   parse or generate wire format, to programmatically set or get values,
#   and to output human-readable values for logging and debug.
#
# While some objects are created with only the base autoObject class, most
#   uses/users will extend the base class for the particular needs of their
#   application; e.g. message or data cache or COM object interface or....
#
# The base class provides the following methods, which may be overridden or
# extended by subclasses:
#
# * *$object* get ?*fieldName*? ?*fieldName* ...?
# * *$object* set *fieldName* *value* ?*fieldName* *value*?
# * *$object* toString
# * *$object* fromList *byteList*
# * *$object* toList
# * *$object* fromByteArray *binaryString*
# * *$object* toByteArray
# * *$object* isInitialized
# * *$object* follow
# * *$object* createWidget
#
# There are two methods used for internal purposes only:
#
# * SortByOffset *arrayName* *a* *b*
# * IterField *fieldName* *args*
#
oo::class create ::autoObject {
    variable BlockSize
    variable DataArray
    variable FieldInfo
    variable Initialized
    variable NameL
    variable Variable_size

    #--------------------------------------------------------------------------
    ### autoObject constructor
    #
    # The constructor takes as input a list defining the object to be created.
    # The defining list has the form of key/valueList pairs, with field names
    # as keys paired with a nested list of up to 6 elements, the first 3
    # of which are mandatory:
    #
    #     { field_offset  # Must start at 0, incr by field_size,
    #                     # leave no gaps.
    #       field_size    # (Max) size of field in bytes in serial
    #                     # input format.
    #       field_type    # Name of the data type. Custom types
    #                     # must support base methods used by
    #                     # autoObject types, may have others.
    #       init_value    # Value used to initialize field data.
    #                     # May be empty {}.
    #       field_data    # Passed to constructor when creating the
    #                     # object of type <field_type>, not used or
    #                     # examined by autoObject.  May be empty {}.
    #       widget_name   # Name of an autoWidget class to use to
    #                     # display the data in GUIs.  May be empty,
    #                     # in which case the autoWidget "autoEntry"
    #                     # will be used if needed.
    #     }
    #
    # If fewer than 6 elements are provided, the remainder will be filled
    # with default values as noted, usually the empty list {}.
    #
    # There is one special reserved field name, "variable_length_object", whose
    # value is a single number defining the minimum size of the object.
    # If the value == 0, it is treated as disabling the special handling (i.e.,
    # the object cannot be variable-size); otherwise, too-small input is
    # changed to a minimum of *$value*, and fields past that size are
    # permitted to be variable in size.  I.e., the object will accept a
    # serial input of any size between *$value* and *blockSize* without
    # complaining, filling fields in order until it runs out of input.
    # If the last field is given some data but not enough bytes to fill it
    # correctly, it is left to the field object to complain; the containing
    # autoObject will not.
    #
    constructor { defineL } {
        logger::import -all -force -namespace log ::autoObject
;#log::setlevel debug

        array set definingArr $defineL
        set currOffset 0
        set Variable_size 0
        set Initialized false
        # There are multiple times we'll want the list of field names sorted by
        # the field offset, so we do the sort once and save it for the future.
        set NameL [lsort -command "my SortByOffset definingArr" \
                   [array names definingArr]]

        # As we read the field list to initialize the fields, parse the
        # sizes and offsets to validate the input.  There should be no
        # missing bytes in the structure.
        foreach field $NameL {
            # Take the special token "variable_length_object" out of the
            # NameL - we don't want to treat it like a normal field.
            if {$field eq "variable_length_object"} {
                log::debug "$field: $definingArr($field)"
                set Variable_size $definingArr($field)
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

            # Find the data type corresponding to the name.  Start by parsing
            # out any array syntax.  Then look in various namespaces to find
            # a definition of the type.
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
            } elseif {[lsearch [info class instances oo::class] "*$tname"] \
                        != -1} {
                # Found a class defined in a different namespace; we either try
                # it or die in error, so we may as well keep going and try it.
                log::debug "class list: \
                            [info class instances oo::class ::AutoObject::*]"
                set msg "No $tname in expected namespace. \
                            Found %s and will try it."
                set tname [lindex [info class instances oo::class] \
                           [lsearch [info class instances oo::class] "*$tname"]]
                log::info [format $msg $tname]
            } else {
                # Can't find a class with that name.  Error out.
                log::error "Unknown type requested: $tname"
                log::error "List of autoObject classes: \
                            [info class instances oo::class ::AutoObject::*]"
                log::error "List of classes: [info class instances oo::class]"
                error "Unknown type requested: $tname"
            }
            set FieldInfo($field,tname) $tname
            set FieldInfo($field,arrcnt) $arrcount
            # Unpack & store the rest of the defining information.
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
                if {$wname eq "self"} {
                    set widgetName "self"
                } elseif {"::AutoObject::$wname" in \
                            [info class instances oo::class ::AutoObject::*]} {
                    # Found widget as a type declared in the appropriate namespace
                    set widgetName "::AutoObject::$wname"
                } elseif {[lsearch [info class instances oo::class] "*$wname"] != -1} {
                    # Found something not in the right namespace; we either try it
                    # or die in error, so we may as well keep going and try it.
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
            # Create the field objects within the container object.
            # First check to see if field is an array of objects.
            if {$isarray} {
                # Validate that size is an integral number of bytes per entry
                set bytesPerObj [expr {int($FieldInfo($field,size) / $arrcount)}]
                if {$arrcount * $bytesPerObj != $FieldInfo($field,size)} {
                    error "Size not an integer multiple of array count.\n\
                           Array count: $arrcount, size: $FieldInfo($field,size)"
                }
                # If we weren't given an exact list of initializer data,
                # assume what we were given is for one element.  Replicate
                # it to cover all elements.
                if {([llength $initData] != $arrcount) && ($initData ne {})} {
                    set initData [lrepeat $arrcount $initData]
                }
                set DataArray($field) {}
                # Create *arrcount* new objects of the specified type and
                # store them in a list in this field.
                for {set idx 0} {$idx < $arrcount} {incr idx} {
                    if [catch {set obj [$tname new $typeData]}] {
                        error "Failed to create new object of type\
                               $tname for field $field element $idx:\
                               $::errorInfo"
                    }
                    if {$initData ne {}} {
                        $obj set [lindex $initData $idx]
                    }
                    # Mix in the GUI class for each object
                    if {$widgetName ne "self"} {
                        oo::objdefine $obj [list mixin $widgetName]
                    }
                    lappend DataArray($field) $obj
                }
                # Forward the field name as a method name to a special
                # method that iterates across the list of objects in the field,
                # runs whatever method of the item the user wants on each one,
                # and collects the results in a list that is returned.
                oo::objdefine [self] forward $field my IterField $field
            } else {
                # Single object, not an array.  Just create & init it.
                if [catch {set DataArray($field) [$tname new $typeData]}] {
                    error "Failed to create new object of type\
                           $tname for field $field: $::errorInfo"
                }
                if {$initData ne {}} {
                    $DataArray($field) set $initData
                }
                # Mix in the GUI class
                if {$widgetName ne "self"} {
                    oo::objdefine $DataArray($field) [list mixin $widgetName]
                }
                # Forward the field name as a method name to the object that
                # the field is composed of.
                oo::objdefine [self] forward $field $DataArray($field)
            }
            # Export the forwarded method so users can call it.
            oo::objdefine [self] export $field
        }
        set BlockSize $currOffset
    }

    #----------------------------------------------------------------------
    ##### autoObject.isInitialized
    #
    # Status getter.  Initialized is set false on creation, true on fromList
    # or fromWire.
    method isInitialized {} {return $Initialized}

    #----------------------------------------------------------------------
    #### autoObject.get
    #
    # Field getter: accepts an args list of keys, and returns a list of values
    # for each key provided or a single value for a single key.  If no key is
    # provided, returns the entire data array in a single list with
    # alternating keys & values, as if from *array get*.
    # Warns on unknown keys or uninitialized object.
    method get {args} {
        set outL {}
        if {![my isInitialized]} {
            log::warn "Reading from uninitialized object [self object] of\
                            type [info object class [self object]]"
        }
        # No keys: return name/value pairs for all defined fields.
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
        # Single key: look up field, return value (if field is array, return list)
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
                    log::error "Requesting non-existant field in\
                            [info object class [self object]] [self object]: \
                            \"$args\" not in \"[array names DataArray]\""
                }
            }
        # Multiple keys: return list of values in order of keys provided.
        # If a field is an array, the list of values will be nested as a single
        # item in the output list.
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
                    log::error "Requesting non-existant field in\
                            [info object class [self object]] [self object]: \
                            \"$key\" not in \"[array names DataArray]\""
                }
            }
        }
        return $outL
    }


    #--------------------------------------------------------------------------
    #### autoObject.set
    #
    # Simple mutator: accepts a list of key/value pairs, and for each key sets
    # the associated value to the supplied value.
    # Warns on but does not reject unknown keys.  Unknown keys have values
    # stored in the data array and can be retrieved with *get*, but are not
    # involved in *toList*/*fromList* operations.
    method set {args} {
        if {[llength $args] %2 == 1} {
            error "Odd number of arguments for set - \
                        set requires key/value pairs only."
        }
        foreach {key val} $args {
            log::debug "$key: $val"
            if {$key eq "Initialized"} {
                set Initialized $val
                continue
            } elseif {$key ni $NameL} {
                log::warn "Warning: trying to set non-standard field in \
                        [info object class [self object]] [self object]: \
                        $key <- $val"
                set $DataArray($key) $val
                continue
            }
            # Check for arrayed objects or single object
            if {$FieldInfo($key,arrcnt) != 0} {
                if {$Variable_size == 0} {
                    # Fixed length array of objects
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
                    # Variable length array of objects - reject if the data
                    # is too long, or so small that it's not big enough to
                    # fill the minimum.
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
        set Initialized true
    }

    #--------------------------------------------------------------------------
    #### autoObject.follow
    #
    # Returns a fully qualified path to the value of the data object;
    # normally used by GUIs to use a field as a textvariable.  If the data
    # is a list of objects, returns a list of FQPs, one per object.
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
    #### autoObject.createWidget
    #
    # Returns a Tk name of a frame that encloses a grid of name/value paired
    # widgets.  Names are labels; values are whatever widget the value object
    # has mixed in that responds to the createWidget method call.
    # Individual field widgets have the option to add a widget to a special
    # list of large widgets that show up at the bottom of the grid (BigWidgetL).
    method createWidget {wname} {
        my variable MyWidget
        my variable BigWidgetL
        # Create encapsulating frame
        set MyWidget [ttk::frame $wname]
        set BigWidgetL {}
        set row 1
        # @@@ TODO %%% llength NameL is not really the right number for
        # number of rows - doesn't take into account dropped reserved
        # fields or arrays/bitfields that take multiple rows.  Figure
        # out a better count later.
        if {[llength $NameL] > 20} {
            set splitRow [expr {([llength $NameL] + 1)/ 2}]
        } else {
            # Even if we think we don't need to split, split at 35 to
            # keep at the size of the monitor :-P
            set splitRow 35
        }
        set colNum 1
        foreach key $NameL {
            set winName [string tolower $key]
            if {[llength $DataArray($key)] == 1} {
                grid [ttk::label $wname.l$winName -text $key] -column $colNum \
                        -row $row -sticky nsew
                set keyWidget [$DataArray($key) createWidget $wname.$winName]
                # Special support for reserved fields - if no widget
                # is returned, don't try to grid it or add rows.
                if {$keyWidget eq ""} { continue }
                # If creation returns 2 widgets, the first is for the small
                # in-row pace, the second is the large breakout version
                if {[llength $keyWidget] > 1} {
                    lappend BigWidgetL [lindex $keyWidget 1]
                    set keyWidget [lindex $keyWidget 0]
                }
                grid $keyWidget -column [expr $colNum + 1] -row $row -sticky nsew
                incr row
                set FieldInfo($key,widget) $keyWidget
            } else {
                grid [ttk::label $wname.l$winName -text $key] -column $colNum \
                        -row $row -sticky nsew
                set widL {}
                foreach obj $DataArray($key) {
                    set wnum [llength $widL]
                    set objWidget [$obj createWidget $wname.$winName$wnum]
                    # Special support for reserved fields - if no widget
                    # is returned, don't try to grid it or add rows.
                    if {$objWidget eq ""} { continue }
                    # If creation returns 2 widgets, the first is for the small
                    # in-row pace, the second is the large breakout version
                    if {[llength $objWidget] > 1} {
                        lappend BigWidgetL [lindex $objWidget 1]
                        set objWidget [lindex $objWidget 0]
                    }

                    lappend widL $objWidget
                    grid $objWidget -column [expr $colNum + 1] -row $row -padx 4 -sticky nsew
                    incr row
                }
                set FieldInfo($key,widget) $widL
            }
            if {$row > $splitRow} {
                grid columnconfigure $wname $colNum -weight 1
                grid columnconfigure $wname [expr $colNum + 1] -weight 4
                set row 1
                incr colNum 2
            }
        }
        grid columnconfigure $wname $colNum -weight 1
        grid columnconfigure $wname [expr $colNum + 1] -weight 4
        set row [expr {min($splitRow, [llength $NameL])}]
        foreach wid $BigWidgetL {
            incr row
            grid $wid -column 1 -columnspan [expr $colNum + 1] -row $row
        }
        return $MyWidget
    }

    #--------------------------------------------------------------------------
    #### autoObject.fromList *inputList*
    #
    # Setter from byte-list format, as supplied by a decoded message or memory
    # dump. Accepts the byte list, parses it as defined in the associated
    # defining array, and stores it in the object's data array.
    method fromList {dataL} {
;#log::setlevel debug
        set dl [llength $dataL]
        # Check that input is correct size for object
        if {$BlockSize != [llength $dataL]} {
            # In all cases, too large is an error
            if { $dl > $BlockSize } {
                log::error "Input for [info object class [self object]] is too\
                        large!  Length: $dl; should be <= $BlockSize."
            # Block is too small and object is not variable-length
            } elseif { $Variable_size == 0 } {
                log::error "Input for [info object class [self object]] has an\
                        incorrect length: $dl; should be $BlockSize."
            # Variable size is allowed to be smaller but not larger
            } else {
                log::debug "Input for [info object class [self object]] is size\
                        $dl bytes (max allowed is $BlockSize, min is\
                        $Variable_size)."
                # Special case - clear out the existing data, because we
                # won't loop past the end of the 0 byte input block.
                if {$dl == 0} {
                    foreach field $NameL {
                        my set $field 0
                    }
                    return
                }
            }
            log::debug "Data is: $dataL"
        }

        # Input is acceptable.  Process it in field order.
        foreach name $NameL {
            set offset $FieldInfo($name,offset)
            set size $FieldInfo($name,size)
            # Once we're past the end of the list, stop processing.
            if {$offset >= $dl} {
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
;#log::setlevel warn
        set Initialized true
    }

    #--------------------------------------------------------------------------
    #### autoObject.toList
    #
    # Getter to byte-list format, as required e.g. to send to a serial target.
    # Gets the byte-list representations of the field objects in the order
    # defined by the defining array, collects them into a combined byte list,
    # and returns the list.
    method toList {} {
        set outL {}
        # Iterate over the ordered list of field names created by the
        # constructor.
        foreach name $NameL {
            log::debug "Converting $name..."
            set offset $FieldInfo($name,offset)
            if {[llength $outL] != $offset && ($Variable_size == 0
                        || $Variable_size > $offset)} {
                # List should have been the right size coming into each field.
                error "Data list incorrect size starting at $name. \
                        Expected $offset bytes, got [llength $outL] ($outL)."
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
            if {[llength $dataL] != $size && ($Variable_size == 0
                        || $Variable_size > ($offset + $size))} {
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
    #### autoObject.toString
    #
    # Getter to screen format.  For each field, retrieves the value and appends
    # it to the output string in the style defined by the type in the field
    # array.  Displays fields not defined in the defining array at the end,
    # marked as special.
    #
    # This can be overridden by derived classes to create a different default
    # format, but has a nominal implementation in place:  name: value, where
    # the colon is 36 columns from the left margin.
    method toString { {keysL {}} } {
        log::debug ""
        log::debug "    [ info object class [self object] ] [self object]:"
        set outL {}
        if {[llength $keysL] == 0} {
            set keysL $NameL
        }
;#log::setlevel debug
        # Iterate over the ordered list of field names created by the
        # constructor.
        foreach name $keysL {
            set size $FieldInfo($name,size)
            set offset $FieldInfo($name,offset)
            log::debug "$name: $size bytes @ $offset bytes"

            # Set field value string with string from field objects
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
            # Append field name & value strings to output string.
            lappend outL [format "       %35s: %s" $name $outStr]
        }

        # Be sure to document any extra fields in the data dict
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
    ##### autoObject.fromByteArray
    #
    # From e.g. wire format or COM interface.  Converts from binary string to
    # list format, then calls fromList.
    method fromByteArray {byteArray} {
        binary scan $byteArray "cu*" byteList
        my fromList $byteList
    }

    #--------------------------------------------------------------------------
    ##### autoObject.toByteArray
    #
    # To e.g. wire format or COM interface.  Calls toList, then converts from
    # list format to binary string.
    method toByteArray {} {
        set byteList [my toList]
        set byteArray [binary format "c*" $byteList]
        return $byteArray
    }

    #--------------------------------------------------------------------------
    ##### autoObject.SortByOffset
    #
    # helper proc used to sort name list by field offset
    method SortByOffset {arrayname a b} {
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
    ##### autoObject.IterField
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

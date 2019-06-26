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
# Copyright 2015-18, Erik N. Johnson
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

# Exclude if somehow sourced more than once.
if {![namespace exists ::AutoObject] } {
    namespace eval ::AutoObject {
        variable AUTOOBJECT_VERSION 0.11
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
# * *$object* follow
# * *$object* createWidget
#
# The base class also supports the Tk-style configure/cget interface for
# options.  The base class options are only *-initialized*, which indicates if
# this object has had any fields set since creation, and *-level*, which sets
# the level of log messages (per the *logger* package,
# <https://core.tcl.tk/tcllib/doc/trunk/embedded/www/tcllib/files/modules/log/logger.html>).
# Other options can be added by extension.
#
# * *$object* configure *option* *value* ?*option *value* ...?
# * *$object* cget ?*option*?
#
# The base class also has two non-public methods used for internal purposes only:
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
    variable WidgetTopRows
    variable WidgetBotCols
    variable Options

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
        ;# Uncomment this for verbose logging of constructor issues.
        ;#log::setlevel debug

        array set definingArr $defineL
        set BlockSize 0
        set Variable_size 0
        set Initialized false
        set WidgetTopRows 20
        set WidgetBotCols 4
        set Options {-initialized -level}
        # There are multiple times we'll want the list of field names sorted by
        # the field offset, so we do the sort once and save it for the future.
        set NameL [lsort -command "my SortByOffset definingArr" \
                   [array names definingArr]]

        # As we read the field list to initialize the fields, parse the
        # sizes and offsets to validate the input.
        # Important:  there cannot be any missing bytes in the structure.
        foreach field $NameL {
            # Take the special token "variable_length_object" out of the
            # NameL - we don't want to treat it like a normal field.
            if {$field eq "variable_length_object"} {
                log::debug "$field: $definingArr($field)"
                set Variable_size $definingArr($field)
                set idx [lsearch $NameL "variable_length_object"]
                set NameL [lreplace $NameL $idx $idx]
            # For normal fields, call the *addField* method and update the
            # current known size of the object based on the result.
            } else {
                my addField $defineL $field
                set BlockSize [expr {$BlockSize + $FieldInfo($field,size)}]
            }
        }
    }

    destructor {
        log::debug "destroying [self]"
        foreach key $NameL {
            foreach obj $DataArray($key) {
                $obj destroy
            }
        }
    }

    #----------------------------------------------------------------------
    #
    # To allow subclassing operations to use the main autoObject engine to
    # dynamically add new fields to an existing object, the *addField* engine
    # is separately exposed.  Normally this is only called by the constructor,
    # and it should **_NEVER_** be called lightly.  Adding fields without
    # knowing *exactly* what you're doing will almost certainly break your
    # objects.  In particular, normal error checking is not done, and the
    # NameL field that is used to drive the to/from/List/String/etc. methods
    # has to be correctly modified to come back into synch with the field
    # data, where the definition of "correct" will vary in each use case.
    #
    # Most commonly, a type that expects to be subclassed will place the
    # uninterpreted bytes in a byte array field called "payload", which will
    # need to be removed from NameL and replaced by all the fields that comprise
    # that data when subtyped.  Usually the subtype would determined by the
    # contents of "payload", but I'm sure this will be false in some cases I
    # haven't thought of yet.

    ##### autoObject.addField
    #
    # *addField* takes the defining list-of-lists and a field name within
    # that list as inputs.  It creates all of the data objects for that field,
    # placing them in the FieldData array, and defines all of the FieldInfo
    # values that allow the data operations to be carried out.
    #
    method addField {defineL field} {
        array set definingArr $defineL
        set fieldList $definingArr($field)
        log::debug "$field: $fieldList"
        if {$BlockSize != [lindex $fieldList 0]} {
            error "Invalid defining list: at offset\
                   [lindex $fieldList 0], expected $BlockSize"
        }
        set FieldInfo($field,offset) [lindex $fieldList 0]
        set FieldInfo($field,size) [lindex $fieldList 1]

        # First, find the data type corresponding to the name.  Start by
        # parsing out any array syntax.  Then look in various namespaces to
        # find a definition of the type.
        set tname "[lindex $fieldList 2]"
        set isarray [regexp {(.+)\[([0-9]+)\]} $tname -> basename arrcount]
        if {$isarray} {
            set tname $basename
        } else {
            set arrcount 0
        }
        # **Case 1:** Found as a type declared in the appropriate namespace
        if {"::AutoObject::$tname" in \
                [info class instances oo::class ::AutoObject::*]} {
            set tname "::AutoObject::$tname"
        # **Case 2:** Found a class defined in a different namespace; we either
        # try it or die in error, so we may as well keep going and try it.
        } elseif {[lsearch [info class instances oo::class] "*$tname"] \
                    != -1} {
            log::debug "class list: \
                        [info class instances oo::class ::AutoObject::*]"
            set msg "No $tname in expected ::AutoObject:: namespace. \
                        Found %s and will try it."
            set tname [lindex [info class instances oo::class] \
                       [lsearch [info class instances oo::class] "*$tname"]]
            log::info [format $msg $tname]
        # **Case 3:** Can't find a class with that name.  Error out.
        } else {
            log::error "Unknown type requested: $tname"
            log::error "List of autoObject classes: \
                        [info class instances oo::class ::AutoObject::*]"
            log::error "List of other known classes: \
                        [info class instances oo::class]"
            error "Unknown type requested: $tname"
        }
        set FieldInfo($field,tname) $tname
        set FieldInfo($field,arrcnt) $arrcount

        # Second, unpack & store the rest of the defining information.
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
        # Third, attempt to determine the widget type, if one is defined.
        if {([llength $fieldList] > 5) && ([lindex $fieldList 5] ne {})} {
            set wname [lindex $fieldList 5]
            if {$wname eq "self"} {
                set widgetName "self"
            # **Case 1:** Found widget as a type declared in the appropriate namespace
            } elseif {"::AutoObject::$wname" in \
                        [info class instances oo::class ::AutoObject::*]} {
                set widgetName "::AutoObject::$wname"
            # **Case 2:** Found something not in the right namespace; we either try it
            # or die in error, so we may as well keep going and try it.
            } elseif {[lsearch [info class instances oo::class] "*$wname"] != -1} {
                log::debug "class list: [info class instances oo::class ::AutoObject::*]"
                set msg "No $wname in expected namespace.  Found %s and will try it."
                set widgetName [lindex [info class instances oo::class] \
                           [lsearch [info class instances oo::class] "*$wname"]]
                log::info [format $msg $widgetName]
            # **Case 3:** Can't find a widget by that name.  Error out.
            } else {
                log::error "Unknown type requested: $wname"
                log::error "List of autoObject classes: [info class instances oo::class ::AutoObject::*]"
                log::error "List of classes: [info class instances oo::class]"
                error "Unknown type requested: $wname"
            }
        } else {
            set widgetName ::AutoObject::autoEntry
        }
        # Finally, create the field objects within the container object.
        # Start by checking to see if field is an array of objects.
        if {$isarray} {
            # It's an array.  Validate that the total specified data size is
            # an integral number of bytes per entry.
            set bytesPerObj [expr {int($FieldInfo($field,size) / $arrcount)}]
            if {$arrcount * $bytesPerObj != $FieldInfo($field,size)} {
                error "Size not an integer multiple of array count.\n\
                       Array count: $arrcount, size: $FieldInfo($field,size)"
            }
            # If we weren't given an exact list of initializer data, one
            # entry per element, assume what we were given is for one element.
            # Replicate it to cover all elements.
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
                    if {[catch {$obj set [lindex $initData $idx]} result]} {
                        error "Initializing field $field with a new $tname\
                               to index $idx of $initData with result $result"
                    }
                }
                # Mix in the UI class for each object
                if {$widgetName ne "self"} {
                    oo::objdefine $obj [list mixin $widgetName]
                }
                lappend DataArray($field) $obj
            }
            # Forward the field name as a method name to a special
            # method that iterates across the list of objects in the field,
            # runs whatever method of the item the user wants on each one,
            # and collects the results in a list that is returned, and
            # export the forwarded method so users can call it.
            oo::objdefine [self] forward $field my IterField $field
            oo::objdefine [self] export $field
        # It's a single object, not an array.  Just create & init it.
        } else {
            if [catch {set DataArray($field) [$tname new $typeData]}] {
                error "Failed to create new object of type\
                       $tname for field $field: $::errorInfo"
            }
            if {$initData ne {}} {
                $DataArray($field) set $initData
            }
            # Mix in the UI class
            if {$widgetName ne "self"} {
                oo::objdefine $DataArray($field) [list mixin $widgetName]
            }
            # Forward the field name as a method name to the object that
            # the field is composed of, and export the forwarded method
            # so users can call it.
            oo::objdefine [self] forward $field $DataArray($field)
            oo::objdefine [self] export $field
        }
    }

    #----------------------------------------------------------------------
    ##### autoObject.configure
    #
    # Support for the traditional Tk configure operator, which can change
    # the values of the various object options. Pairs with cget.
    #
    # The base class supports the following options:
    #
    # * *-initialized*: sets the internal Initialized flag.
    #           Initialized is set false on creation, set true on
    #           *fromList*, *fromWire*, or *set*.  This only needs
    #           to be overridden to allow a object with all fields
    #           still at default values to be serialized.
    # * *-level*: sets the level of logging, per the *logger* package.
    #           Possible values are : debug, info, notice, warn,
    #           error, critical, alert, and emergency.  Nothing
    #           above error is used in this package.  For details, see
    # <https://core.tcl.tk/tcllib/doc/trunk/embedded/www/tcllib/files/modules/log/logger.html>).
    #
    # To extend this in a subclass, I recommend beginning by calling *next* to
    # allow the base case to handle the errors and its own options, then
    # (assuming no errors) handling your own options.  E.g.:
    #
    #       method configure {args} {
    #           next {*}$args
    #           foreach {opt value} $args {
    #               switch -exact -- $opt {
    #                   -myOption {
    #                       # does things
    #                   }
    #               }
    #           }
    #       }
    #
    # Also, note that the Options base class variable should have your new
    # options appended in the constructor.  E.g.:
    #
    #       my variable Options
    #       lappend Options "-myOption"
    method configure {args} {
        if {[llength $args] == 0} {
            my variable Options
            return $Options
        } elseif {[llength $args] % 2 != 0} {
            throw [list MSGCHAN OPTION_FORMAT $args]\
                "Options and values must be given in pairs, got \"$args\""
        } else {
            foreach {opt value} $args {
                switch -exact -- $opt {
                    -initialized {
                        my variable Initialized
                        set Initialized $value
                    }
                    -level {
                        log::setlevel $value
                    }
                }
            }
        }
    }
    #----------------------------------------------------------------------
    ##### autoObject.cget
    #
    # Support for the traditional Tk cget operator, which returns
    # the values of the various object options. Pairs with configure.
    #
    # The base class supports the following options:
    #
    # * *-initialized*: returns the internal Initialized flag.
    #               Initialized is set false on creation, set true on
    #               *fromList*, *fromWire*, or *set*.
    # * *-level*: returns the level of logging, per the *logger* package.
    #               Possible values are : debug, info, notice, warn,
    #               error, critical, alert, and emergency.  For details, see
    # <https://core.tcl.tk/tcllib/doc/trunk/embedded/www/tcllib/files/modules/log/logger.html>).
    #
    # To extend this in a subclass, I recommend beginning by checking your own
    # options first, then falling through on default to call *next* to allow
    # the base case to handle the errors and its own options.  Also, the
    # Options class variable should have your new options appended in the
    # constructor as noted above.  E.g.:
    #
    #       method cget {option} {
    #           switch -exact -- $option {
    #               -myOption {
    #                   return $MyOptionValue
    #               }
    #               default {
    #                   return [next $option]
    #               }
    #           }
    #       }
    method cget {option} {
        switch -exact -- $option {
            -initialized {
                return $Initialized
            }
            -level {
                return [log::currentloglevel]
            }
            default {
                my variable Options
                throw [list MSGCHAN UNKNOWN_OPTION $option]\
                    "unknown option, \"$option\", should be one of\
                    [join $Options ,]"
            }
        }
    }

    #----------------------------------------------------------------------
    ##### autoObject.isInitialized
    #
    # **DEPRECATED**  Status getter.  Initialized is set false on creation,
    # set true on *fromList*, *fromWire*, or *set*.  Reading values from an
    # uninitialized object will generate a warning.  If the object is only
    # partially initialized before being read, the user is responsible for not
    # using values of uninitialized fields.
    #
    # This method is from an early implementation before the cget/configure
    # interface was added, and is not recommended for future design.
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
                    log::error "Requesting non-existent field in\
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
                    log::error "Requesting non-existent field in\
                            [info object class [self object]] [self object]: \
                            \"$key\" not in \"[array names DataArray]\""
                }
            }
        }
        return $outL
    }


    #----------------------------------------------------------------------
    #### autoObject.getObj
    #
    # Special field getter that returns embedded data objects: accepts an args
    # list of a single key, and returns the object or list of objects that
    # comprise that key's field. If no key is provided, or if a list of keys is
    # provided, throws an error (user almost certainly wanted *get*, not
    # *getObj*).
    #
    # In general, if you don't know why you'd want the base object(s) instead
    # of the value(s) of the object(s), you don't want to use this method.
    #
    # Warns on unknown keys or uninitialized object.
    method getObj {args} {
        set outL {}
        if {![my isInitialized]} {
            log::warn "Reading from uninitialized object [self object] of\
                            type [info object class [self object]]"
        }
        # No keys: throw an error
        if {$args == {}} {
            error "No key provided to \"getObj\" for object [self object] of\
                            type [info object class [self object]]"
        # Single key: look up field, return object (if field is array, return
        # list of objects).
        } elseif {[llength $args] == 1} {
            if {$args in $NameL} {
                if {[llength $DataArray($args)] > 1} {
                    set tempL {}
                    foreach obj $DataArray($args) {
                        lappend tempL $obj
                    }
                    return $tempL
                } else {
                    return $DataArray($args)
                }
            } elseif {[info exists DataArray($args)]} {
                return $DataArray($args)
            } else {
                my variable $args
                if {[info exists $args]} {
                    return [set $args]
                } else {
                    log::error "Requesting non-existent field in\
                            [info object class [self object]] [self object]: \
                            \"$args\" not in \"[array names DataArray]\""
                }
            }
        # Multiple keys: throw error
        } else {
            error "Too many keys provided to \"getObj\" for object [self object] of\
                            type [info object class [self object]]"
        }
        return $outL
    }


    #--------------------------------------------------------------------------
    #### autoObject.set *key/valueList*
    #
    # Simple mutator: accepts a list of key/value pairs, and for each key sets
    # the associated value to the supplied value.
    # Warns on but does not reject unknown keys.  Unknown keys have values
    # stored in the data array and can be retrieved with *get*, but are not
    # involved in *toList*/*fromList* operations.
    method set {args} {
        if {[llength $args] %2 == 1} {
            error "Odd number of arguments ([llength $args]) for set - \
                        set requires key/value pairs only."
        }
        foreach {key val} $args {
            log::debug "setting $key: $val"
            if {$key eq "Initialized"} {
                set Initialized $val
                continue
            }
            if {$key ni $NameL} {
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
            set Initialized true
        }
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
    # widgets.  Names are labels; values are whatever widget the field object
    # has mixed in that responds to the *createWidget* method call.
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
        # out a better count later.  Cap it at 20 to ensure it fits on
        # most monitors.
        set splitRow [expr {min($WidgetTopRows, ([llength $NameL] + 1)/ 2)}]
        set colNum 1
        # Iterate over all fields, creating pairs of labels (for name)
        # and display widgets (for values).
        foreach key $NameL {
            set winName [string tolower $key]
            # First, handle non-array fields
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
            # Handle field arrays by creating one name label for all, and one
            # value display widget per object in the array.
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
            # Columns over 20 items get unwieldy, and don't fit well on smaller
            # monitors.
            # @@@ TODO %%% make this value configurable & save in .ini file.
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
            } elseif { $Variable_size > [llength $dataL]} {
                log::error "Input for [info object class [self object]] has an\
                        incorrect length: $dl; (max allowed is $BlockSize,\
                        min is $Variable_size)."
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

            # Cut off the next field's data from the input list
            set byteL [lrange $dataL $offset [expr {$offset + $size - 1}]]
            log::debug "Getting $name value from dataL($offset -\
                    [expr {$offset + $size - 1}]): $byteL"
            # Single value field
            if {[llength $DataArray($name)] == 1} {
                $DataArray($name) fromList $byteL
                log::debug "$name set to [$DataArray($name) get]"
            # Array field
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
                # For each object in the array, cut off the right number of
                # bytes and feed it to them.
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
    # Getter to byte-list format (a list of numbers 0-255 representing bytes).
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

        # Just in case, convert to list of non-negative byte values (range 0-255)
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
    # byte-list format, then calls fromList.
    method fromByteArray {byteArray} {
        binary scan $byteArray "cu*" byteList
        my fromList $byteList
    }

    #--------------------------------------------------------------------------
    ##### autoObject.toByteArray
    #
    # To e.g. wire format or COM interface.  Calls toList, then converts from
    # byte-list format to binary string.
    method toByteArray {} {
        set byteList [my toList]
        set byteArray [binary format "c*" $byteList]
        return $byteArray
    }

    #--------------------------------------------------------------------------
    ##### autoObject.SortByOffset
    #
    # helper method used to sort name list by field offset
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
    # helper method used to forward commands to an autoData field if the field
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
package provide autoObject $::AutoObject::AUTOOBJECT_VERSION

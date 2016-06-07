#!/bin/sh
# -*- tcl -*-
# The next line is executed by /bin/sh, but not tcl \
exec tclsh "$0" ${1+"$@"}


lappend auto_path ".."
puts "autoObject version: [package require autoObject]"
package require struct::list

set firstDefList {
    FieldOne    {0   4   uint32_t   1       {}  }
    FieldTwo    {4   1   uint8_t    150     {}  }
    FieldThree  {5   3   uint8_t[3] {1 2 3} {}  }
    FieldFour   {8   4   float_t    3.141590118408203    {}  }
    FieldFive   {12  2   uint16_t   50000   {}  }
    FieldSix    {14  1   int8_t     -5      {}  }
    FieldSeven  {15  4   time_t     "" {"%Y-%m-%d %H:%M:%S"}  }
    FunkyField  {19  1   myEnum     0       {}  }
    StrField    {20  15  string_t   "How you like me now, motherf***er?" 15 }
}

#--------------------------------------------------------------------------
#   my special enum type
#
oo::class create myEnum {
    superclass ::AutoObject::uint8_t
    mixin ::AutoObject::enum_mix

    method extraSpecial {tweak} {
        my variable MyValue
        set MyValue [expr {($MyValue + $tweak) % 3}]
    }
}
setEnumDef ::myEnum {
    "False"             0   
    "True"              1   
    "File Not Found"    2   
}


#set ::verbose true
set ::verbose false


set initL {FieldOne 1 FieldTwo 150 FieldThree {1 2 3} FieldFour 3.141590118408203 \
            FieldFive 50000 FieldSix -5 FieldSeven}
# Keep setting of "currTime" and creation of object as close together as
# possible to increase likelihood that the time in both will be the same.
set currTime [clock seconds]
set firstObject [autoObject new $firstDefList]
lappend initL $currTime
lappend initL FunkyField 0 StrField "How you like me"

# Test initialization
puts "From intialization:"
puts [$firstObject toString]
set valueL [$firstObject get]
if {![struct::list equal $valueL $initL]} {
    error "Initialization/get failed:\n\tExpected: $initL\n\tActual:   $valueL"
} else {
    puts "Initialization/get PASS"
}
puts ""

# Test set
puts "Setting fields:"
$firstObject set FunkyField "True" FieldThree {4 5 6} FieldOne 987654321
set setL [lreplace $valueL 1 1 987654321]
set setL [lreplace $setL 5 5 {4 5 6}]
set setL [lreplace $setL 15 15 1]
set valueL [$firstObject get]
if {![struct::list equal $valueL $setL]} {
    error "Set failed:\n\tExpected: $setL\n\tActual:   $valueL"
} else {
    puts "Set PASS"
}
puts ""

# Test toList
puts "To List:"
set saveL {177 104 222 58 150 4 5 6 208 15 73 64 80 195 251}
lappend saveL [expr { $currTime & 0x000000FF}]
lappend saveL [expr {($currTime & 0x0000FF00) >> 8}]
lappend saveL [expr {($currTime & 0x00FF0000) >> 16}]
lappend saveL [expr {($currTime & 0xFF000000) >> 24}]
lappend saveL 1 72 111 119 32 121 111 117 32 108 105 107 101 32 109 101
puts [$firstObject toList]
set valueL [$firstObject toList]
if {![struct::list equal $valueL $saveL]} {
    error "toList failed:\n\tExpected: $saveL\n\tActual:   $valueL"
} else {
    puts "toList PASS"
}
puts ""

# Test toByteArray
puts "Save to Byte Array..."
set valueBA [$firstObject toByteArray]
set expectBA [binary format "c*" $saveL]
if {![string equal $valueBA $expectBA]} {
    error "toByteArray failed:\n\tExpected: [binary scan $expectBA "c*"]\n\tActual:   [binary scan $valueBA "c*"]"
} else {
    puts "toByteArray PASS"
}
puts ""

# Test fromList
set list1 {1 0 1 0 96 10 9 -10 -48 99 73 64 120 232 175 0 0 0 0 2 \
                110 111 119 44 32 109 111 116 104 101 114 102 42 42 42}
$firstObject fromList $list1
puts "From modified list:"
puts [$firstObject toString]
set valueL [$firstObject get]
set expectL {FieldOne 65537 FieldTwo 96 FieldThree {10 9 246} FieldFour 3.146717071533203 \
             FieldFive 59512 FieldSix -81 FieldSeven 0 FunkyField 2 StrField "now, motherf***"}
if {![struct::list equal $valueL $expectL]} {
    error "from modified list failed:\n\tExpected: $expectL\n\tActual:   $valueL"
} else {
    puts "from modified list PASS"
}
puts ""

# Test fromByteArray
$firstObject fromByteArray $valueBA
puts "Restored from Byte Array"
puts [$firstObject toString]
set valueL [$firstObject get]
if {![struct::list equal $valueL $setL]} {
    error "fromByteArray restore failed:\n\tExpected: $setL\n\tActual:   $valueL"
} else {
    puts "fromByteArray restore PASS"
}

# Test forwarded commands
puts "\nForwarding toList command to fields:"
puts "object: [info object methods $firstObject]"
puts "class:  [info class methods [info object class $firstObject]]"
foreach {field paramlist} $firstDefList {
    puts [format "Field Name: %20s : %s " $field [$firstObject $field toList] ]
}
puts "\nArray method test: FieldThree is [$firstObject FieldThree get]"
puts "\nSpecial method test: FunkyField was [$firstObject FunkyField toString]"
$firstObject FunkyField extraSpecial 4
puts "special method test: FunkyField now [$firstObject FunkyField toString]"
if {[$firstObject get FunkyField] != 2} {
    error "forwarded special method failed:\n\tExpected: 2\n\tActual:   [$firstObject get FunkyField]"
} else {
    puts "forwarded special method PASS"
}


puts ""
puts "All Tests PASS"



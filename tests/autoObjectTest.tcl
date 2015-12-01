#!/bin/sh
# -*- tcl -*-
# The next line is executed by /bin/sh, but not tcl \
exec tclsh "$0" ${1+"$@"}


lappend auto_path ".."
package require autoObject
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
    StrField    {20  15  string_t   "How you like me now, motherfucker?" 15 }
}

#--------------------------------------------------------------------------
#   my special enum type
#
oo::class create myEnum {
    superclass ::AutoData::uint8_t
    variable enumStrings

    constructor {args} {
        next $args
        array set enumStrings {
            0   "False"
            1   "True"
            2   "File Not Found"
        }
    }
    method toString {} {
        my variable MyValue
        return $enumStrings($MyValue)
    }
}


set initL {FieldOne 1 FieldTwo 150 FieldThree 1 2 3 FieldFour 3.141590118408203 \
            FieldFive 50000 FieldSix -5 FieldSeven}
set currTime [clock seconds]
set firstObject [autoObject new $firstDefList]
lappend initL $currTime
lappend initL FunkyField 0 StrField "How you like me"

puts "From intialization:"
puts [$firstObject toString]
set valueL [$firstObject get]
if {![struct::list equal $valueL $initL]} {
    error "Initialization/get failed:\n\tExpected: $initL\n\tActual:   $valueL"
} else {
    puts "Initialization/get PASS"
}
puts ""

puts "To List:"
set expectL {1 0 0 0 150 1 2 3 208 15 73 64 80 195 251}
lappend expectL [expr { $currTime & 0x000000FF}]
lappend expectL [expr {($currTime & 0x0000FF00) >> 8}]
lappend expectL [expr {($currTime & 0x00FF0000) >> 16}]
lappend expectL [expr {($currTime & 0xFF000000) >> 24}]
lappend expectL 0 72 111 119 32 121 111 117 32 108 105 107 101 32 109 101
puts [$firstObject toList]
set valueL [$firstObject toList]
if {![struct::list equal $valueL $expectL]} {
    error "toList failed:\n\tExpected: $expectL\n\tActual:   $valueL"
} else {
    puts "toList PASS"
}
puts ""

puts "Saved to Byte Array..."
set valueBA [$firstObject toByteArray]
set expectBA [binary format "c*" $expectL]
if {![string equal $valueBA $expectBA]} {
    error "toByteArray failed:\n\tExpected: [binary scan $expectBA "c*"]\n\tActual:   [binary scan $valueBA "c*"]"
} else {
    puts "toByteArray PASS"
}
puts ""

set list1 {1 0 1 0 96 10 9 -10 -48 99 73 64 120 232 175 0 0 0 0 2 109 111 116 104 101 114 102 117 99 107 101 114 63 0 0}
$firstObject fromList $list1
puts "From modified list:"
puts [$firstObject toString]
set valueL [$firstObject get]
set expectL {FieldOne 65537 FieldTwo 96 FieldThree 10 9 246 FieldFour 3.146717071533203 \
             FieldFive 59512 FieldSix -81 FieldSeven 0 FunkyField 2 StrField "motherfucker?"}
if {![struct::list equal $valueL $expectL]} {
    error "fromByteArray failed:\n\tExpected: $expectL\n\tActual:   $valueL"
} else {
    puts "fromByteArray PASS"
}
puts ""

$firstObject fromByteArray $valueBA
puts "Restored from Byte Array"
puts [$firstObject toString]
set valueL [$firstObject get]
if {![struct::list equal $valueL $initL]} {
    error "fromByteArray restore failed:\n\tExpected: $initL\n\tActual:   $valueL"
} else {
    puts "fromByteArray restore PASS"
}
puts ""
puts "All Tests PASS"


set ::verbose true
set ::verbose false
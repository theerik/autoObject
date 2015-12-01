#!/bin/sh
# -*- tcl -*-
# The next line is executed by /bin/sh, but not tcl \
exec tclsh "$0" ${1+"$@"}


lappend auto_path "."
package require autoObject

array set firstDefArray {
    FieldOne    {0   4   uint32_t    1      {}  }
    FieldTwo    {4   1   uint8_t     150    {}  }
    FieldThree  {5   3   uint8_t[3]  {1 2 3}    {}  }
    FieldFour   {8   4   float_t     3.14159    {}  }
    FieldFive   {12  2   uint16_t    50000  {}  }
    FieldSix    {14  1   int8_t      -5     {}  }
    FieldSeven  {15  4   time_t      "" {"%Y-%m-%d %H:%M:%S"}  }
}

set firstObject [autoObject new firstDefArray]
puts "From intialization:"
puts [$firstObject toString]
puts "To List:"
puts [$firstObject toList]
puts "Saved to Byte Array..."
set ba1 [$firstObject toByteArray]

set list1 {1 0 1 0 96 10 9 -10 -48 99 73 64 120 232 175 0 0 0 0}
$firstObject fromList $list1
puts "From modified list"
puts [$firstObject toString]
$firstObject fromByteArray $ba1
puts "Restored from Byte Array"
puts [$firstObject toString]

set ::verbose true
set ::verbose false
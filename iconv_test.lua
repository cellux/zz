local iconv = require('iconv')
local assert = require('assert')

assert.equals(iconv.utf8_strlen("árvíztűrő tükörfúrógép"), 22)

assert.equals(iconv.utf8_codepoints("árvíztűrő tükörfúrógép"),
              { 0x00e1, 0x0072, 0x0076, 0x00ed,
                0x007a, 0x0074, 0x0171, 0x0072,
                0x0151, 0x0020, 0x0074, 0x00fc,
                0x006b, 0x00f6, 0x0072, 0x0066,
                0x00fa, 0x0072, 0x00f3, 0x0067,
                0x00e9, 0x0070 })

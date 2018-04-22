local testing = require('testing')
local uri = require('uri')
local assert = require('assert')
local inspect = require('inspect')

local function assert_equiv(uri_repr, uri_data)
   -- parsing uri_repr results in uri_data
   assert.equals(uri(uri_repr), uri_data)
   -- stringifying uri_data results in uri_repr
   assert.equals(tostring(uri(uri_data)), uri_repr)
end

-- see https://tools.ietf.org/html/rfc3986

testing("uri", function()
   assert.equals(uri(), nil)
   assert.equals(uri(""), nil)

   -- 1.1.2 Examples

   assert_equiv("ftp://ftp.is.co.za/rfc/rfc1808.txt", {
      scheme = "ftp",
      host = "ftp.is.co.za",
      path = "/rfc/rfc1808.txt"
   })
   
   assert_equiv("http://www.ietf.org/rfc/rfc2396.txt", {
      scheme = "http",
      host = "www.ietf.org",
      path = "/rfc/rfc2396.txt"
   })
   
   assert_equiv("ldap://[2001:db8::7]/c=GB?objectClass?one", {
      scheme = "ldap",
      host = "[2001:db8::7]",
      path = "/c=GB",
      query = "objectClass?one"
   })
   
   assert_equiv("mailto:John.Doe@example.com", {
      scheme = "mailto",
      path = "John.Doe@example.com"
   })
   
   assert_equiv("news:comp.infosystems.www.servers.unix", {
      scheme = "news",
      path = "comp.infosystems.www.servers.unix"
   })
   
   assert_equiv("tel:+1-816-555-1212", {
      scheme = "tel",
      path = "+1-816-555-1212"
   })
   
   assert_equiv("telnet://192.0.2.16:80/", {
      scheme = "telnet",
      host = "192.0.2.16",
      port = "80",
      path = "/"
   })
   
   assert_equiv("urn:oasis:names:specification:docbook:dtd:xml:4.1.2", {
      scheme = "urn",
      path = "oasis:names:specification:docbook:dtd:xml:4.1.2"
   })
   
   -- 2.1. Percent-Encoding
   
   -- A percent-encoded octet is encoded as a character triplet,
   -- consisting of the percent character "%" followed by the two
   -- hexadecimal digits representing that octet's numeric value.
   
   assert_equiv("http://example.com/Cheech%20%26%20Chong%20Travelling%20In%20Neverland.mkv", {
      scheme = "http",
      host = "example.com",
      path = "/Cheech & Chong Travelling In Neverland.mkv",
   })
   
   -- The uppercase hexadecimal digits 'A' through 'F' are equivalent to
   -- the lowercase digits 'a' through 'f', respectively.
   
   -- If two URIs differ only in the case of hexadecimal digits used in
   -- percent-encoded octets, they are equivalent.
   
   assert.equals(uri("http://example.com/%7euser"),
                 uri("http://example.com/%7Euser"))
   
   -- For consistency, URI producers and normalizers should use uppercase
   -- hexadecimal digits for all percent-encodings.
   
   assert_equiv("http://example.com/What%27s%20the%20deal%3F.mkv", {
      scheme = "http",
      host = "example.com",
      path = "/What's the deal?.mkv"
   })
   
   -- 2.3. Unreserved characters
   
   -- URIs that differ in the replacement of an unreserved character with
   -- its corresponding percent-encoded US-ASCII octet are equivalent:
   -- they identify the same resource.
   
   assert.equals(uri("http://example.com/%7Euser"),
                 uri("http://example.com/~user"))
   
   -- 2.4. When to Encode or Decode
   
   -- Because the percent ("%") character serves as the indicator for
   -- percent-encoded octets, it must be percent-encoded as "%25" for
   -- that octet to be used as data within a URI.
   
   assert_equiv("http://example.com/The%20100%25%20rule.mkv", {
      scheme = "http",
      host = "example.com",
      path = "/The 100% rule.mkv"
   })
   
   -- control characters
   
   assert_equiv("http://example.com/%00%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F", {
      scheme = "http",
      host = "example.com",
      path = "/\0\1\2\3\4\5\6\7\8\9\10\11\12\13\14\15\16\17\18\19\20\21\22\23\24\25\26\27\28\29\30\31"
   })
   
   -- UTF-8 characters
   
   assert_equiv("http://example.com/%C3%A1rv%C3%ADzt%C5%B1r%C5%91/t%C3%BCk%C3%B6rf%C3%BAr%C3%B3g%C3%A9p", {
      scheme = "http",
      host = "example.com",
      path = "/árvíztűrő/tükörfúrógép"
   })
   
   -- 3. Syntax components
   
   -- The scheme and path components are required, though the path may be
   -- empty (no characters).
   
   assert_equiv("unknown:", {
      scheme = "unknown",
      path = ""
   })
   
   -- When authority is present, the path must either be empty or begin
   -- with a slash ("/") character.
   
   assert_equiv("http://example.com", {
      scheme = "http",
      host = "example.com",
      path = ""
   })
   
   assert_equiv("http://example.com/abc", {
      scheme = "http",
      host = "example.com",
      path = "/abc"
   })
   
   assert.throws("path must be empty or begin with a slash character", function()
      tostring(uri {
         scheme = "http",
         host = "example.com",
         path = "abc"
      })
   end)
   
   -- When authority is not present, the path cannot begin with two slash
   -- characters ("//").
   
   assert.throws("path cannot begin with two slash characters", function()
      tostring(uri {
         scheme = "http",
         path = "//abc"
      })
   end)
   
   -- example URIs and their component parts
   
   assert_equiv("foo://example.com:8042/over/there?name=ferret#nose", {
      scheme = "foo",
      host = "example.com",
      port = "8042",
      path = "/over/there",
      query = "name=ferret",
      fragment = "nose",
   })
   
   -- 3.1. Scheme
   
   -- Scheme names consist of a sequence of characters beginning with a
   -- letter and followed by any combination of letters, digits, plus
   -- ("+"), period ("."), or hyphen ("-").
   
   assert.throws("missing scheme", function()
      tostring(uri {
         path = ""
      })
   end)
   
   assert.throws("invalid scheme", function()
      tostring(uri {
         scheme = "01234",
         path = ""
      })
   end)
   
   assert.throws("invalid scheme", function()
      uri("árvíz://dzsunga")
   end)
   
   -- An implementation should accept uppercase letters as equivalent to
   -- lowercase in scheme names (e.g., allow "HTTP" as well as "http")
   -- for the sake of robustness but should only produce lowercase scheme
   -- names for consistency.
   
   assert.equals(tostring(uri { scheme = "HTTP" }), "http:")
   assert.equals(uri("HTTP:"), { scheme = "http", path = "" })
   
   -- 3.2. Authority
   
   -- URI producers and normalizers should omit the ":" delimiter that
   -- separates host from port if the port component is empty.
   
   assert_equiv("http://example.com:1234/index.html", {
      scheme = "http",
      host = "example.com",
      port = "1234",
      path = "/index.html"
   })
   
   assert_equiv("http://example.com/index.html", {
      scheme = "http",
      host = "example.com",
      path = "/index.html"
   })
   
   -- 3.2.1. User Information
   
   assert_equiv("http://user@example.com/index.html", {
      scheme = "http",
      host = "example.com",
      user = "user",
      path = "/index.html"
   })
   
   assert_equiv("http://user:password@example.com/index.html", {
      scheme = "http",
      host = "example.com",
      user = "user",
      password = "password",
      path = "/index.html"
   })
   
   assert_equiv("http://u%3As%40r%20%23%25%2F%3F:pass%3Aw%40rd%20%23%25%2F%3F@example.com/index.html", {
      scheme = "http",
      host = "example.com",
      user = "u:s@r #%/?",
      password = "pass:w@rd #%/?",
      path = "/index.html"
   })
   
   -- 3.2.2. Host
   
   -- Although host is case-insensitive, producers and normalizers should
   -- use lowercase for registered names.
   
   assert.equals(tostring(uri {
      scheme = "http",
      host = "EXAMPLE.COM"
   }), "http://example.com")
   
   assert.equals(uri("http://EXAMPLE.COM"), {
      scheme = "http",
      host = "example.com",
      path = ""
   })
   
   -- IPv6 literals
   
   assert_equiv("https://[2001:db8:85a3:8d3:1319:8a2e:370:7348]:443/", {
      scheme = "https",
      host = "[2001:db8:85a3:8d3:1319:8a2e:370:7348]",
      port = "443",
      path = "/"
   })
   
   -- IPv4 address
   
   assert_equiv("https://192.168.144.235:443/", {
      scheme = "https",
      host = "192.168.144.235",
      port = "443",
      path = "/"
   })
   
   -- reg-name
   
   assert_equiv("https://static.facebook.com:443/1x1.gif", {
      scheme = "https",
      host = "static.facebook.com",
      port = "443",
      path = "/1x1.gif"
   })
   
   -- URI producing applications must not use percent-encoding in host
   -- unless it is used to represent a UTF-8 character sequence.
   --
   -- ... meh, let the users care about that.
   
   -- 3.3. Path
   
   assert_equiv("foo://info.example.com?fred", {
      scheme = "foo",
      host = "info.example.com",
      path = "",
      query = "fred"
   })
   
   -- 3.4. Query
   
   assert_equiv("http://example.com?a=1&b=2&c=/root/file%23marker", {
      scheme = "http",
      host = "example.com",
      path = "",
      query = "a=1&b=2&c=/root/file#marker"
   })
   
   -- 3.5. Fragment
   
   -- The characters slash ("/") and question mark ("?") are allowed to
   -- represent data within the fragment identifier.
   
   assert_equiv("http://example.com?fear#?love/suffering", {
      scheme = "http",
      host = "example.com",
      path = "",
      query = "fear",
      fragment = "?love/suffering"
   })
   
   -- 6.2.2.3. Path Segment Normalization: TODO
end)

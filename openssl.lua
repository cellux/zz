local ffi = require('ffi')
local util = require('util')
local buffer = require('buffer')

ffi.cdef [[

/*** library initialization ***/

/* before OpenSSL 1.1.0 */
int SSL_library_init(void);

void OPENSSL_add_all_algorithms_noconf(void);
void OPENSSL_add_all_algorithms_conf(void);

void OpenSSL_add_all_ciphers(void);
void OpenSSL_add_all_digests(void);

/* since OpenSSL 1.1.0 */

enum {
  OPENSSL_INIT_NO_LOAD_CRYPTO_STRINGS = 0x00000001,
  OPENSSL_INIT_LOAD_CRYPTO_STRINGS    = 0x00000002,
  OPENSSL_INIT_ADD_ALL_CIPHERS        = 0x00000004,
  OPENSSL_INIT_ADD_ALL_DIGESTS        = 0x00000008,
  OPENSSL_INIT_NO_ADD_ALL_CIPHERS     = 0x00000010,
  OPENSSL_INIT_NO_ADD_ALL_DIGESTS     = 0x00000020,
  OPENSSL_INIT_LOAD_CONFIG            = 0x00000040,
  OPENSSL_INIT_NO_LOAD_CONFIG         = 0x00000080,
  OPENSSL_INIT_ASYNC                  = 0x00000100,
  OPENSSL_INIT_ENGINE_RDRAND          = 0x00000200,
  OPENSSL_INIT_ENGINE_DYNAMIC         = 0x00000400,
  OPENSSL_INIT_ENGINE_OPENSSL         = 0x00000800,
  OPENSSL_INIT_ENGINE_CRYPTODEV       = 0x00001000,
  OPENSSL_INIT_ENGINE_CAPI            = 0x00002000,
  OPENSSL_INIT_ENGINE_PADLOCK         = 0x00004000,
  OPENSSL_INIT_ENGINE_AFALG           = 0x00008000
};

int OPENSSL_init_ssl(uint64_t opts, const void *settings);

/*** digests ***/

struct env_md_ctx_st;
struct env_md_st;
struct engine_st;

typedef struct env_md_ctx_st EVP_MD_CTX;
typedef struct env_md_st EVP_MD;
typedef struct engine_st ENGINE;

EVP_MD_CTX *EVP_MD_CTX_create(void); /* before OpenSSL 1.1.0 */
EVP_MD_CTX *EVP_MD_CTX_new(void); /* since OpenSSL 1.1.0 */

int EVP_DigestInit_ex(EVP_MD_CTX *ctx, const EVP_MD *type, ENGINE *impl);
int EVP_DigestUpdate(EVP_MD_CTX *ctx, const void *d, size_t cnt);
int EVP_DigestFinal_ex(EVP_MD_CTX *ctx, unsigned char *md, unsigned int *s);

const EVP_MD *EVP_get_digestbyname(const char *name);

int EVP_MD_type(const EVP_MD *md);
int EVP_MD_pkey_type(const EVP_MD *md);
int EVP_MD_size(const EVP_MD *md);
int EVP_MD_block_size(const EVP_MD *md);

static const int EVP_MAX_MD_SIZE = 64; /* SHA512 */

void EVP_MD_CTX_destroy(EVP_MD_CTX *ctx); /* before OpenSSL 1.1.0 */
void EVP_MD_CTX_free(EVP_MD_CTX *ctx); /* since OpenSSL 1.1.0 */

]]

local ssl = ffi.load("ssl")

-- initialize library

local function libssl_has_fn(name)
   return pcall(function() return ssl[name] end)
end

if libssl_has_fn("OPENSSL_init_ssl") then
   local opts = bit.bor(
      ssl.OPENSSL_INIT_LOAD_CRYPTO_STRINGS,
      ssl.OPENSSL_INIT_ADD_ALL_CIPHERS,
      ssl.OPENSSL_INIT_ADD_ALL_DIGESTS,
      ssl.OPENSSL_INIT_NO_LOAD_CONFIG
   )
   ssl.OPENSSL_init_ssl(opts, nil)
elseif libssl_has_fn("SSL_library_init") then
   ssl.SSL_library_init()
   ssl.OPENSSL_add_all_algorithms_noconf()
else
   ef("Cannot initialize OpenSSL library: none of the known initialization functions can be found")
end

local M = {}

local EVP_MD_CTX_new, EVP_MD_CTX_free
if libssl_has_fn("EVP_MD_CTX_new") and libssl_has_fn("EVP_MD_CTX_free") then
   EVP_MD_CTX_new = ssl.EVP_MD_CTX_new
   EVP_MD_CTX_free = ssl.EVP_MD_CTX_free
elseif libssl_has_fn("EVP_MD_CTX_create") and libssl_has_fn("EVP_MD_CTX_destroy") then
   EVP_MD_CTX_new = ssl.EVP_MD_CTX_create
   EVP_MD_CTX_free = ssl.EVP_MD_CTX_destroy
else
   ef("EVP_MD_CTX initializer/finalizer functions cannot be found")
end

function M.Digest(digest_type)
   local ctx = EVP_MD_CTX_new()
   local md = ssl.EVP_get_digestbyname(digest_type)
   if md == nil then
      ef("Unknown digest type: %s", digest_type)
   end
   util.check_ok("EVP_DigestInit_ex", 1, ssl.EVP_DigestInit_ex(ctx, md, nil))
   local self = {}
   function self:update(buf, size)
      util.check_ok("EVP_DigestUpdate", 1, ssl.EVP_DigestUpdate(ctx, buf, size or #buf))
   end
   function self:final()
      local md_size = ssl.EVP_MD_size(md)
      local buf = buffer.new(md_size, md_size)
      util.check_ok("EVP_DigestFinal_ex", 1, ssl.EVP_DigestFinal_ex(ctx, buf.ptr, nil))
      EVP_MD_CTX_free(self.ctx)
      self.ctx = nil
      return buf
   end
   return self
end

return setmetatable(M, { __index = ssl })

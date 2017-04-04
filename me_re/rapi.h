#ifndef _RAPI_H_
#define _RAPI_H_

// RAPI header
#define RAPI_BASE_ADDRESS	((void *) 0x20000000)
#define RAPI_MAGIC		0x49504152 // "RAPI" in ascii
#define RAPI_VERSION		0x0005

#define FLASH_ME_REGION		0x400000

#define TO_U32(addr)		*((uint32_t *) addr)
#define TO_U16(addr)		*((uint16_t *) addr)
#define TO_U8(addr)		*((uint8_t *) addr)

typedef struct {
  uint32_t magic;
  void *rapi0_tab;
  void *rapi2_tab;
  uint16_t rapi_version;
  uint16_t unknown;
} RapiHeader_s;

typedef struct {
  uint32_t name;
  uint32_t owner;
  uint32_t offset;
  uint32_t size;
  uint32_t tokens_on_start;
  uint32_t max_tokens;
  uint32_t scratch_sectors;
  uint32_t flags;
} FPTEntry_s;

typedef struct {
  uint8_t romb_vector[0x10];
  uint32_t sig;
  uint32_t num_entries;
  uint8_t bcd_ver;
  uint8_t fpt_entry_type;
  uint8_t header_len;
  uint8_t checksum;
  uint16_t flash_cycle_lifetime;
  uint16_t flash_cycle_limit;
  uint32_t uma_size;
  uint32_t flags;
  uint32_t field_18;
  uint32_t field_1c;
  FTPEntry_s entries[0];
} FPTHeader_s;


typedef struct {
  uint32_t tag; // 0x00
  char name[16]; // 0x04
  char hash[32]; // 0x14
  uint32_t load_address; // 0x34
  MmeModule_s *module; // 0x38
  uint32_t load_length; // 0x3C
  uint32_t module_length; // 0x40
  uint32_t memory_size; // 0x44
  uin32_t pre_uma_size; // 0x48
  void * entry_point; // 0x4C
  uint32_t flags; // 0x50
  uint32_t reserved; // 0x54
} MmeHeader_s;

typedef struct {
  uint16_t type; // 0x00
  uint16_t sub_type; // 0x02
  uint32_t header_len; // 0x04
  uint32_t header_version; // 0x08
  uint32_t flags; // 0x0C
  uint32_t module_vendor; // 0x10
  uint32_t date; // 0x14
  uint32_t size; // 0x18
  uint32_t tag; // 0x1C
  uint32_t num_modules; // 0x20
  uint16_t major_version; // 0x24
  uint16_t minor_version; // 0x26
  uint16_t hotfix_version; // 0x28
  uint16_t build_version; // 0x2A
  uint32_t padding_byte; // 0x2C
  uint8_t field_30[72]; // 0x30
  uint32_t key_size; // 0x78
  uint32_t scratch_size; // 0x7C
  uint8_t rsa_pub_key[256]; // 0x80
  uint32_t rsa_pub_exponent; // 0x180
  uint8_t rsa_signature[256]; // 0x184
  uint8_t partition_name[12]; // 0x284
  MmeHeader_s module_entries[0]; // 0x290
} MeManifestHeader_s;

typedef struct {
  uint32_t sig;
  uint32_t dw_size;
  uint8_t field_8;
  uint8_t field_9;
  uint8_t field_a;
  uint8_t field_b;
  uint32_t anonymous_0;
  uint8_t field_10[0x20];
  uint8_t field_30[0x20];
  uint8_t field_50[0x20];
  uint8_t byte_21F3F890[0x20];
  uint8_t field_90[0x10];
  uint8_t field_A0[0x10];
  uint8_t field_B0[0x40];
  uint8_t field_F0[0x10];
  uint8_t field_100[0x70];
  uint8_t field_170[0x20];
  uint32_t field_190
} PavpData1_s;

typedef struct {
  uint32_t sig;
  uint32_t dw_size;
  uint8_t field_8[24];
  uint8_t field_20[8];
  uint8_t field_28[24];
  uint32_t field_40;
  uint32_t field_44;
  uint32_t field_48;
} PavpData2_s;

typedef struct {
  void *hash_ptrs[8];
  uint16_t num_keys;
  uint16_t key_mask;
} KeyHashes_s;

static const RapiHeader_s * RAPI_HEADER = (RapiHeader_s *) RAPI_BASE_ADDRESS;
static const PavpData1_s *g_pavp1 = ((PavpData1_s *) 0x21F3F820);
static const PavpData2_s *g_pavp2 = ((PavpData2_s *) 0x21F3F9B4);
static const PavpData1_s **rapi_ptr_pavp1 = (RAPI_BASE_ADDRESS + 0x504);
static const PavpData2_s **rapi_ptr_pavp2 = (RAPI_BASE_ADDRESS + 0x518);
static const MeManifestHeader_s *g_manifest0 = ((MeManifestHeader_s *) 0x20026000);
static const MeManifestHeader_s **rapi_ptr_manifest0 = (RAPI_BASE_ADDRESS + 0x4E4);
static const KeyHashes_s *g_known_keys = ((KeyHashes_s *)0x21F7E604);
static const KeyHashes_s **rapi_known_keys = (RAPI_BASE_ADDRESS + 0x51C);

void (*RAPI_memset) (void *addr, uint32_t value, uint32_t size) = (RAPI_BASE_ADDRESS + 0xA7C);
int (*RAPI_strncmp) (const char *a, const char *b, uint32_t size) = (RAPI_BASE_ADDRESS + 0xA84);
void (*RAPI_go_to_error_state) (uint32_t aux_reg_10005, uint32_t aux_reg_10011) = (RAPI_BASE_ADDRESS + 0x18);
void (*RAPI_ac_push_13_to_20) () =(RAPI_BASE_ADDRESS + 0xCF4);
MmeHeader_s *(*RAPI_find_module) (const char *module_name, uint32_t arg,
				  MeManifestHeader_s *manifest, uint32_t arg2) = (RAPI_BASE_ADDRESS + 0x80);
uint32_t (*RAPI_check_fpt_header) (FPTHeader_s *header) = (RAPI_BASE_ADDRESS + 0x60);
FPTEntry_t *(*RAPI_find_partition) (const char *module_name, uint32_t arg,
				  FPTHeader_s *fpt, uint32_t arg2) = (RAPI_BASE_ADDRESS + 0x68);
uint32_t (*RAPI_manifest_checksig) (MeManifestHeader_s *input, KeyHashes_s *,
				    MeManifestHeader_s *output, uint32_t flag) = (RAPI_BASE_ADDRESS + 0x88);

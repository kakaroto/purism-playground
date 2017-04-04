#include <rapi.h>

// some MMIO addresses ?
#define FLAG_ADDRESS1		0x8000C038
#define FLAG_ADDRESS2		0x80008FA0
#define FLAG_VALUE		TO_U16(FLAG_ADDRESS1)

#define ROMP_RAM_ADDRESS	((void *) 0x200d3000)
#define ROMP_SCRATCH_AREA	((void *) 0x21000000)

typedef struct {
  void *romp_address;
  uint32_t romp_size;
  MmeHeader_s *bup_module;
  void * flag_address;
  uint32_t aux_reg_8011[7]; // Timestamps at various moments in the code?
} RompData_s;

static const RompData_s *ROMP_DATA = ROMP_RAM_ADDRESS;

static uint32_t *AUX_REGS = NULL; // Auxiliary registers

void validate_RAPI_and_version(int arg1, int arg2) {
  if (RAPI_HEADER->magic != RAPI_MAGIC ||
      RAPI_HEADER->version != RAPI_VERSION) {
    // TODO: figure out what is auxiliary register 0x10005 ?
    // Probably a status code? 
    AUX_REG[0x10005] = (AUX_REG[0x10005] & 0xFFFF0FFF) | 0x3000;
    while (1) halt(); // Sets the Halt processor control flag.
  } 
}

void ROMP_start(int arg1, int arg2) {
  MmeHeader_s *module;

  RAPI_ac_push_13_to_20(); // Pushes registers 13 to 20. No idea why it's a RAPI, and not inline

  // TODO: figure out what is auxiliary register 0x10011 ?
  // Does it matter that the store happens twice ? 
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF);

  RAPI_memset(&ROMP_DATA, 0, sizeof(ROMP_DATA) /*0x2C*/);
  ROMP_DATA->aux_reg_8011[0] = AUX_REG[0x8011];
  
  module = RAPI_find_module("ROMP", 1, *rapi_ptr_manifest0, 0);

  ROMP_DATA->romp_address = module->load_address;
  ROMP_DATA->romp_size = module->memory_size;
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFFFFBFFF); // Clear 14th bit

  ROMP_DATA->flag_address = FLAG_ADDRESS1;
  if ((TO_U32(FLAG_ADDRESS2 + 0x78) & 0x20000) == 0x20000) {
    if ((FLAG_VALUE & 0x400) == 0x400) {
      FLAG_VALUE |= 0x80; // Sets bit 7
      FLAG_VALUE &= 0xFFFFFBFF; // Clears bit 10
    }
    FLAG_VALUE |= 0x400; // Sets bit 10
  } else {
    FLAG_VALUE &= 0xFBFF; // Clears bit 10
  }
  if ((FLAG_VALUE & 0x300) != 0) {
    uint16 flag = FLAG_VALUE;

    // Perform a -1 on bits 8 and 9 and store it back
    flag = ((((flag >> 8) & 0x3) - 1) & 0x3) << 8;
    FLAG_VALUE = (FLAG_VALUE & 0xFFFFFCFF) | flag;
    // Basically checks if the flag value was 0x100 before we modified it ?
    if ((FLAG_VALUE & 0x300) == 0) {
      FLAG_VALUE |= 0x80; // Sets bit 7
    }
  }
  // Same  code as at the start of the function, but now we OR with 0x10000
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF) | 0x10000;
  
  // if it takes 2 args, then r1 is FLAG_ADDRESS1
  if (RAPI_check_fpt_header(FLASH_ME_REGION) != 0) {
    FTPEntry_s *nftp;

    ROMP_DATA->aux_reg_8011[1] = AUX_REG[0x8011]; // We stored it in 0x10 before, and 0x18 later
    nfpt = RAPI_find_partition("NFTP", 1, FLASH_ME_REGION, 0);
    ROMP_DATA->aux_reg_8011[2] = AUX_REG[0x8011]; // We stored it in 0x10 before, and 0x18 later
    
    if (nftp != NULL) {
      MeManifestHeader_s *nftp_manifest;
      MeManifestHeader_s *scratch = (MeManifestHeader_s *) ROMP_SCRATCH_AREA;

      nftp_manifest = FLASH_ME_REGION + nftp->offset;
      if (nftp_manifest->tag == 0x324E4D24) { // "$MN2" tag
	if (RAPI_strncmp(nftp_manifest->partition_name, "FTPR", 4) == 0) {
	  rom_lock_mem_range(ROMP_SCRATCH_AREA, 0x8000, 0x50032, 0);
	  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
	  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF) | 0x20000;
	  if (RAPI_manifest_checksig(nftp_manifest, *rapi_known_keys,
				     scratch, 0x8000) != 0) {
	    ROMP_DATA->aux_reg_8011[3] = AUX_REG[0x8011];
	    AUX_REG[0x10011] = AUX_REG[0x10011] | 0x4000;
	    
	    if ((FLAG_VALUE & 0x80) == 0) {
	      if ((FLAG_VALUE & 0x300) <= 0) {
		uint32 partition_size = scratch->size;
		uint32 lut_offset;
		void *module_ptr;
		void *upper_limit;

		// BUG!!!!! It doesn't shift the partition size by 2 when locking the range
		// This means that there will be a part of the manifest that will not be
		// range locked.
		mem_lock_mem_range(*rapi_ptr_manifest0, partition_size, 0x50032, 0);
		// This seems to be doing a DMA copy from the scratch area
		// into the manifest0 address
		RAPI_20000030(*rapi_ptr_manifest0, scratch, partition_size << 2);

		// Ignore padding to align on 0x40 bytes boundaries
		lut_offset = ((*rapi_ptr_manifest0->size << 2) + 0x3f) & 0xFFFFFFC0;
		// does r1 remain valid after the call to previous function? does setup_spi_for_lut need more than 1 arg?
		j_setup_spi_for_lut(nftp_manifest + lut_offset); 

		module_ptr = *rapi_ptr_manifest0 + 0x290;
		upper_limit = module_ptr + (*rapi_ptr_manifest0->num_modules * 0x60);
		while (module_ptr < upper_limit) {
		  // Add nftp_manifest pointer to LUT_OFFSET value
		  // This transforms the LUT_OFFSET value into an actual pointer to the module
		  // in the flash ME Region
		  ((MmeHeader_s *) module_ptr)->module += nftp_manifest;
		}
	      }
	    }
	  }
	  mem_unlock_mem_range(ROMP_SCRATCH_AREA, 0x8000, 2);
	}
      }
    }
  }
  
  // I wonder if it's debug logging the value of 0x8011 in its internal
  // structure at different points in the code?
  ROMP_DATA->aux_reg_8011[4] = AUX_REG[0x8011];
  if (*rapi_ptr_pavp1->field_a != 0) {
    if (*rapi_ptr_pavp1->field_9 > *rapi_ptr_pavp1->field_a) {
      if ((FLAG_VALUE & 0x10) != 0) {
	*rapi_ptr_pavp1->field_9 = *rapi_ptr_pavp1->field_a;
	*rapi_ptr_pavp1->field_a = 0;
	RAPI_memcpy(*rapi_ptr_pavp1->field_10, 0x20, *rapi_ptr_pavp1->field_30, 0x20);
	RAPI_memset(*rapi_ptr_pavp1->field_30, 0, 0x20);
	RAPI_memset(*rapi_ptr_pavp1->field_50, 0, 0x20);
	RAPI_dma_start(*rapi_ptr_pavp1, sizeof(PavpData1_s) /*0x194*/, 0);
      }
    }
  }
  // Same  code as at the start of the function, but now we OR with 0x30000
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF) | 0x30000;
  
  module = RAPI_rapi_find_module("BUP", 1, *rapi_ptr_manifest0, 0);
  ROMP_DATA->bup_module = module;
  ROMP_DATA->aux_reg_8011[5] = AUX_REG[0x8011];
  if (module != NULL) {
    // Same  code as at the start of the function, but now we OR with 0x40000
    AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
    AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF) | 0x40000;
    if (load_module(module, 0xC0) == 0) {
      ROMP_DATA->aux_reg_8011[6] = AUX_REG[0x8011];
      module->flags |= 0x1;
      // Same  code as at the start of the function, but now we OR with 0x50000
      AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
      AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF) | 0x50000;
      // Looks like will start (jump to) the BUP module, giving it ROMP's internal RAM
      // address as argument (which has ROMP's find_module result + 0x34, then + 0x44,
      // the module object of BUP, the address of FLAG_ADDRESS1, then the debug of aux 0x8011.
      module->entry_point(ROMP_DATA);
    }
  }
    
  RAPI_go_to_error_state((AUX_REG[0x10005] & 0xFFFF0FFF) | 0x3000, AUX_REG[0x10011]);
  return;
}

void entrypoint(int arg1, int arg2) {
  validate_RAPI_and_version(arg1, arg2);
  ROMP_start(arg1, arg2);
}

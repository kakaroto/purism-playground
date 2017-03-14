// RAPI header
#define RAPI_BASE_ADDRESS	0x20000000
#define RAPI_MAGIC		0x49504152 // "RAPI" in ascii
#define RAPI_VERSION		0x0005
// RAPI methods
#define RAPI_UNK_80		(RAPI_BASE_ADDRESS + 0x80)
#define RAPI_memset_A7C		(RAPI_BASE_ADDRESS + 0xA7C)
#define RAPI_UNK_CF4		(RAPI_BASE_ADDRESS + 0xCF4)

// RAPI values/structs?
#define RAPI_4E4		(RAPI_BASE_ADDRESS + 0x4E4)
#define RAPI_504		(RAPI_BASE_ADDRESS + 0x504)
#define RAPI_51C		(RAPI_BASE_ADDRESS + 0x51C)

#define TO_U32(addr)		*((uint32 *) addr)
#define TO_U16(addr)		*((uint16 *) addr)
#define TO_U8(addr)		*((uint8 *) addr)
#define FLAG_ADDRESS1		0x8000C038
#define FLAG_ADDRESS2		0x80008FA0
#define FLAG_VALUE		TO_U16(FLAG_ADDRESS1)

#define RAM_ADDRESS		0x200d3000
#define RAM(index)		TO_U32(RAM_ADDRESS + index)

void validate_RAPI_and_version(int arg1, int arg2) {
  if (TO_U32(RAPI_BASE_ADDRESS) != RAPI_MAGIC ||
      TO_U16(RAPI_BASE_ADDRESS + 0xC) != RAPI_VERSION) {
    // TODO: figure out what is auxiliary register 0x10005 ?
    AUX_REG[0x10005] = (AUX_REG[0x10005] & 0xFFFF0FFF) | 0x3000;
    while (1) halt(); // Sets the Halt processor control flag.
  } 
}

void ROMP_start(int arg1, int arg2) {
  void *module;
  char *rapi_504_ptr;

  RAPI_UNK_CF4(arg1, arg2); // Unknown RAPI, no idea if it uses args
  // TODO: figure out what is auxiliary register 0x10011 ?
  // Does it matter that the store happens twice ? 
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF);

  RAPI_memset_A7C(RAM_ADDRESS, 0, 0x2C);
  RAM(0x10) = AUX_REG[0x8011];

  module = j_rapi_find_module("ROMP", 1, TO_U32(RAPI_4E4), 0);

  RAM(0) = TO_U32(module + 0x34); 
  RAM(4) = TO_U32(module + 0x44);
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFFFFBFFF); // Clear 14th bit

  RAM(0xC) = FLAG_ADDRESS1;
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
  if (j_check_fpt_header(0x400000) != 0) {
    void *nftp;

    RAM(0x14) = AUX_REG[0x8011]; // We stored it in 0x10 before, and 0x18 later
    nfpt = j_find_partition("NFTP", 1, 0x400000, 0);
    RAM(0x18) = AUX_REG[0x8011]; // We stored it in 0x10 before, and 0x18 later
    
    if (nftp != NULL) {
      void *nftp_data;

      nftp_data = nftp->field_8 + 0x400000;
      if (TO_U32(nftp_data + 0x1C) == 0x324E4D24) { // "$MN2" tag
	if (strncmp(nftp_data + 0x284, "FTPR", 4) == 0) {
	  rom_lock_mem_range(0x21000000, 0x8000, 0x50032, 0);
	  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
	  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF) | 0x20000;
	  if (j_manifest_checksig(nftp_data, TO_U32(RAPI_51C),
				  0x21000000, 0x8000) != 0) {
	    RAM(0x1C) = AUX_REG[0x8011];
	    AUX_REG[0x10011] = AUX_REG[0x10011] | 0x4000;
	    
	    if ((FLAG_VALUE & 0x80) == 0) {
	      if ((FLAG_VALUE & 0x300) <= 0) {
		uint32 partition_size = TO_U32(0x21000018);
		uint32 lut_offset;
		void *rapi_4e4_ptr = TO_U32(RAPI_4E4);
		void *module_ptr;
		void *upper_limit;
		uint32 numModules;

		mem_lock_mem_range(rapi_4e4_ptr, partition_size, 0x50032, 0);
		// Does this copy the partition from 0x21000000 into the rapi_4e4_ptr area?
		// That's because the partition size is TO_U32(0x21000000 + 0x18) and after this
		// it starts to be calculated using TO_U32(rapi_4e4_ptr + 0x18)
		unk_20000030(rapi_4e4_ptr, 0x21000000, partition_size << 2);

		// Ignore padding to align on 0x40 bytes boundaries
		lut_offset = ((TO_U32(rapi_4e4_ptr + 0x18) << 2) + 0x3f) & 0xFFFFFFC0;
		// does r1 remain valid after the call to previous function? does setup_spi_for_lut need more than 1 arg?
		j_setup_spi_for_lut(nftp_data + lut_offset); 

		numModules = TO_U32(rapi_4e4_ptr + 0x20);
		upper_limit = rapi_4e4_ptr + 0x290 + (numModules * 60);
		module_ptr = rapi_4e4_ptr + 0x290;
		while (module_ptr < upper_limit) {
		  // Add nftp_data pointer to LUT_OFFSET value
		  // TODO: need to understand the difference between the data in
		  // the pointers : nftp_data, rapi_4e4_ptr and 0x210000000
		  // And why there are so many copies, or do they all point to the same thing
		  TO_U32(module_ptr + 0x38) += nftp_data;
		}
	      }
	    }
	  }
	  mem_unlock_mem_range(0x21000000, 0x8000, 2);
	}
      }
    }
  }
  
  // I wonder if it's debug logging the value of 0x8011 in its internal
  // structure at different points in the code?
  RAM(0x20) = AUX_REG[0x8011];
  rapi_504_ptr = TO_U32(RAPI_504);
  if (rapi_504_ptr[10] != 0) {
    if (rapi_504_ptr[9] > rapi_504_ptr[10]) {
      if ((FLAG_VALUE & 0x10) != 0) {
	rapi_504_ptr[9] = rapi_504_ptr[10];
	rapi_504_ptr[10] = 0;
	memcpy(rapi_504_ptr + 0x10, 0x20, rapi_504_ptr + 0x30, 0x20);
	memcpy(rapi_504_ptr + 0x30, 0, 0x20);
	memcpy(rapi_504_ptr + 0x50, 0, 0x20);
	dma_start(rapi_504_ptr, 0x194, 0);
      }
    }
  }
  // Same  code as at the start of the function, but now we OR with 0x30000
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF) | 0x30000;
  
  module = j_rapi_find_module("BUP", 1, TO_U32(RAPI_4E4), 0);
  RAM(0x8) = module;
  RAM(0x24) = AUX_REG[0x8011];
  if (module != NULL) {
    // Same  code as at the start of the function, but now we OR with 0x40000
    AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
    AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF) | 0x40000;
    if (load_module(module, 0xC0) == 0) {
      RAM(0x28) = AUX_REG[0x8011];
      module[0x50] |= 0x1;
      // Same  code as at the start of the function, but now we OR with 0x50000
      AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
      AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF) | 0x50000;
      // Looks like will start (jump to) the BUP module, giving it ROMP's internal RAM
      // address as argument (which has ROMP's find_module result + 0x34, then + 0x44,
      // the module object of BUP, the address of FLAG_ADDRESS1, then the debug of aux 0x8011.
      module[0x4C](RAM);
    }
  }
    
  go_to_error_state((AUX_REG[0x10005] & 0xFFFF0FFF) | 0x3000, AUX_REG[0x10011]);
  return;
}

void entrypoint(int arg1, int arg2) {
  validate_RAPI_and_version(arg1, arg2);
  ROMP_start(arg1, arg2);
}

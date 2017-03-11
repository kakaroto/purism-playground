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

#define TO_U32(addr)		*((uint32 *) addr)
#define TO_U16(addr)		*((uint16 *) addr)
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
  uint8 *unk_80;

  RAPI_UNK_CF4(arg1, arg2); // Unknown RAPI, no idea if it uses args
  // TODO: figure out what is auxiliary register 0x10011 ?
  // Does it matter that the store happens twice ? 
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0x0FFFFFFF) | 0x80000000; 
  AUX_REG[0x10011] = (AUX_REG[0x10011] & 0xFF00FFFF);

  RAPI_memset_A7C(RAM_ADDRESS, 0, 0x2C);
  RAM(0x10) = AUX_REG[0x8011];

  unk_80 = RAPI_UNK_80("ROMP", 1, TO_U32(RAPI_4E4), 0);
  RAM(0) = TO_U32(unk_80 + 0x34); 
  RAM(4) = TO_U32(unk_80 + 0x44);
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
  
  
}

void entrypoint(int arg1, int arg2) {
  validate_RAPI_and_version(arg1, arg2);
  ROMP_start(arg1, arg2);
}

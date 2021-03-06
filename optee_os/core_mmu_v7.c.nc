#include <arm.h>
#include <assert.h>
#include <keep.h>
#include <kernel/panic.h>
#include <kernel/tlb_helpers.h>
#include <kernel/thread.h>
#include <mm/core_memprot.h>
#include <mm/core_mmu.h>
#include <mm/pgt_cache.h>
#include <platform_config.h>
#include <stdlib.h>
#include <string.h>
#include <trace.h>
#include <util.h>
#include "core_mmu_private.h"
#ifdef CFG_WITH_LPAE
#error This file is not to be used with LPAE
#endif
#ifndef DEBUG_XLAT_TABLE
#define DEBUG_XLAT_TABLE 0
#endif
#if DEBUG_XLAT_TABLE
#define debug_print(...) DMSG_RAW(__VA_ARGS__)
#else
#define debug_print(...) ((void)0)
#endif
#define TEE_MMU_TTB_S           (1 << 1)
#define TEE_MMU_TTB_NOS         (1 << 5)
#define TEE_MMU_TTB_IRGN_NC     0
#define TEE_MMU_TTB_IRGN_WBWA   (1 << 6)
#define TEE_MMU_TTB_IRGN_WT     1
#define TEE_MMU_TTB_IRGN_WB     (1 | (1 << 6))
#define TEE_MMU_TTB_RNG_WBWA    (1 << 3)
#define TEE_MMU_TTB_RNG_WB      (3 << 3)
#ifndef CFG_NO_SMP
#define TEE_MMU_DEFAULT_ATTRS \
		(TEE_MMU_TTB_S | TEE_MMU_TTB_NOS | \
		 TEE_MMU_TTB_IRGN_WBWA | TEE_MMU_TTB_RNG_WBWA)
#else
#define TEE_MMU_DEFAULT_ATTRS (TEE_MMU_TTB_IRGN_WB | TEE_MMU_TTB_RNG_WB)
#endif
#define INVALID_DESC		0x0
#define HIDDEN_DESC		0x4
#define HIDDEN_DIRTY_DESC	0x8
#define SECTION_SHIFT		20
#define SECTION_MASK		0x000fffff
#define SECTION_SIZE		0x00100000
#define SECTION_SECURE			(0 << 19)
#define SECTION_NOTSECURE		(1 << 19)
#define SECTION_SHARED			(1 << 16)
#define SECTION_NOTGLOBAL		(1 << 17)
#define SECTION_ACCESS_FLAG		(1 << 10)
#define SECTION_UNPRIV			(1 << 11)
#define SECTION_RO			(1 << 15)
#define SECTION_TEXCB(texcb)		((((texcb) >> 2) << 12) | \
					 ((((texcb) >> 1) & 0x1) << 3) | \
					 (((texcb) & 0x1) << 2))
#define SECTION_DEVICE			SECTION_TEXCB(ATTR_DEVICE_INDEX)
#define SECTION_NORMAL			SECTION_TEXCB(ATTR_DEVICE_INDEX)
#define SECTION_NORMAL_CACHED		SECTION_TEXCB(ATTR_NORMAL_CACHED_INDEX)
#define SECTION_XN			(1 << 4)
#define SECTION_PXN			(1 << 0)
#define SECTION_SECTION			(2 << 0)
#define SECTION_PT_NOTSECURE		(1 << 3)
#define SECTION_PT_PT			(1 << 0)
#define SECTION_PT_ATTR_MASK		~((1 << 10) - 1)
#define SMALL_PAGE_SMALL_PAGE		(1 << 1)
#define SMALL_PAGE_SHARED		(1 << 10)
#define SMALL_PAGE_NOTGLOBAL		(1 << 11)
#define SMALL_PAGE_TEXCB(texcb)		((((texcb) >> 2) << 6) | \
					 ((((texcb) >> 1) & 0x1) << 3) | \
					 (((texcb) & 0x1) << 2))
#define SMALL_PAGE_DEVICE		SMALL_PAGE_TEXCB(ATTR_DEVICE_INDEX)
#define SMALL_PAGE_NORMAL		SMALL_PAGE_TEXCB(ATTR_DEVICE_INDEX)
#define SMALL_PAGE_NORMAL_CACHED	SMALL_PAGE_TEXCB(ATTR_NORMAL_CACHED_INDEX)
#define SMALL_PAGE_ACCESS_FLAG		(1 << 4)
#define SMALL_PAGE_UNPRIV		(1 << 5)
#define SMALL_PAGE_RO			(1 << 9)
#define SMALL_PAGE_XN			(1 << 0)
#define ATTR_DEVICE_INDEX		0x0
#define ATTR_NORMAL_CACHED_INDEX	0x1
#define PRRR_IDX(idx, tr, nos)		(((tr) << (2 * (idx))) | \
					 ((uint32_t)(nos) << ((idx) + 24)))
#define NMRR_IDX(idx, ir, or)		(((ir) << (2 * (idx))) | \
					 ((uint32_t)(or) << (2 * (idx) + 16)))
#define PRRR_DS0			(1 << 16)
#define PRRR_DS1			(1 << 17)
#define PRRR_NS0			(1 << 18)
#define PRRR_NS1			(1 << 19)
#define ATTR_DEVICE_PRRR		PRRR_IDX(ATTR_DEVICE_INDEX, 1, 0)
#define ATTR_DEVICE_NMRR		NMRR_IDX(ATTR_DEVICE_INDEX, 0, 0)
#ifndef CFG_NO_SMP
#define ATTR_NORMAL_CACHED_PRRR		PRRR_IDX(ATTR_NORMAL_CACHED_INDEX, 2, 1)
#define ATTR_NORMAL_CACHED_NMRR		NMRR_IDX(ATTR_NORMAL_CACHED_INDEX, 1, 1)
#else
#define ATTR_NORMAL_CACHED_PRRR		PRRR_IDX(ATTR_NORMAL_CACHED_INDEX, 2, 0)
#define ATTR_NORMAL_CACHED_NMRR		NMRR_IDX(ATTR_NORMAL_CACHED_INDEX, 3, 3)
#endif
#define NUM_L1_ENTRIES		4096
#define NUM_L2_ENTRIES		256
#define L1_TBL_SIZE		(NUM_L1_ENTRIES * 4)
#define L2_TBL_SIZE		(NUM_L2_ENTRIES * 4)
#define L1_ALIGNMENT		L1_TBL_SIZE
#define L2_ALIGNMENT		L2_TBL_SIZE
#define TTBCR_N_VALUE		7
#define NUM_UL1_ENTRIES         (1 << (12 - TTBCR_N_VALUE))
#define UL1_ALIGNMENT		(NUM_UL1_ENTRIES * 4)
#define TTB_UL1_MASK		(~(UL1_ALIGNMENT - 1))
#define TTB_L1_MASK		(~(L1_ALIGNMENT - 1))
#ifndef MAX_XLAT_TABLES
#define MAX_XLAT_TABLES		4
#endif
enum desc_type {
	DESC_TYPE_PAGE_TABLE,
	DESC_TYPE_SECTION,
	DESC_TYPE_SUPER_SECTION,
	DESC_TYPE_LARGE_PAGE,
	DESC_TYPE_SMALL_PAGE,
	DESC_TYPE_INVALID,
};
#ifdef CFG_CORE_UNMAP_CORE_AT_EL0
#define NUM_L1_TABLES	2
#else
#define NUM_L1_TABLES	1
#endif
uint32_t main_mmu_l1_ttb[NUM_L1_TABLES][NUM_L1_ENTRIES]
		__aligned(L1_ALIGNMENT) __section(".nozi.mmu.l1");
static uint32_t main_mmu_l2_ttb[MAX_XLAT_TABLES][NUM_L2_ENTRIES]
		__aligned(L2_ALIGNMENT) __section(".nozi.mmu.l2");
static uint32_t main_mmu_ul1_ttb[CFG_NUM_THREADS][NUM_UL1_ENTRIES]
		__aligned(UL1_ALIGNMENT) __section(".nozi.mmu.ul1");
static vaddr_t core_mmu_get_main_ttb_va(void)
{
	return (vaddr_t)main_mmu_l1_ttb[0];
}
static paddr_t core_mmu_get_main_ttb_pa(void)
{
	paddr_t pa = virt_to_phys((void *)core_mmu_get_main_ttb_va());
	if (pa & ~TTB_L1_MASK)
		panic("invalid core l1 table");
	return pa;
}
static vaddr_t core_mmu_get_ul1_ttb_va(void)
{
	return (vaddr_t)main_mmu_ul1_ttb[thread_get_id()];
}
static paddr_t core_mmu_get_ul1_ttb_pa(void)
{
	paddr_t pa = virt_to_phys((void *)core_mmu_get_ul1_ttb_va());
	if (pa & ~TTB_UL1_MASK)
		panic("invalid user l1 table");
	return pa;
}
static void *core_mmu_alloc_l2(size_t size)
{
	static uint32_t tables_used;
	uint32_t to_alloc = ROUNDUP(size, NUM_L2_ENTRIES * SMALL_PAGE_SIZE) /
		(NUM_L2_ENTRIES * SMALL_PAGE_SIZE);
	DMSG("L2 table used: %d/%d", tables_used + to_alloc, MAX_XLAT_TABLES);
	if (tables_used + to_alloc > MAX_XLAT_TABLES)
		return NULL;
	memset(main_mmu_l2_ttb[tables_used], 0,
		sizeof(main_mmu_l2_ttb[0]) * to_alloc);
	tables_used += to_alloc;
	return main_mmu_l2_ttb[tables_used - to_alloc];
}
static enum desc_type get_desc_type(unsigned level, uint32_t desc)
{
	assert(level >= 1 && level <= 2);
	if (level == 1) {
		if ((desc & 0x3) == 0x1)
			return DESC_TYPE_PAGE_TABLE;
		if ((desc & 0x2) == 0x2) {
			if (desc & (1 << 18))
				return DESC_TYPE_SUPER_SECTION;
			return DESC_TYPE_SECTION;
		}
	} else {
		if ((desc & 0x3) == 0x1)
			return DESC_TYPE_LARGE_PAGE;
		if ((desc & 0x2) == 0x2)
			return DESC_TYPE_SMALL_PAGE;
	}
	return DESC_TYPE_INVALID;
}
static uint32_t texcb_to_mattr(uint32_t texcb)
{
	COMPILE_TIME_ASSERT(ATTR_DEVICE_INDEX == TEE_MATTR_CACHE_NONCACHE);
	COMPILE_TIME_ASSERT(ATTR_NORMAL_CACHED_INDEX == TEE_MATTR_CACHE_CACHED);
	return texcb << TEE_MATTR_CACHE_SHIFT;
}
static uint32_t mattr_to_texcb(uint32_t attr)
{
	return (attr >> TEE_MATTR_CACHE_SHIFT) & TEE_MATTR_CACHE_MASK;
}
static uint32_t desc_to_mattr(unsigned level, uint32_t desc)
{
	uint32_t a;
	switch (get_desc_type(level, desc)) {
	case DESC_TYPE_PAGE_TABLE:
		a = TEE_MATTR_TABLE;
		if (!(desc & SECTION_PT_NOTSECURE))
			a |= TEE_MATTR_SECURE;
		break;
	case DESC_TYPE_SECTION:
		a = TEE_MATTR_VALID_BLOCK;
		if (desc & SECTION_ACCESS_FLAG)
			a |= TEE_MATTR_PRX | TEE_MATTR_URX;
		if (!(desc & SECTION_RO))
			a |= TEE_MATTR_PW | TEE_MATTR_UW;
		if (desc & SECTION_XN)
			a &= ~(TEE_MATTR_PX | TEE_MATTR_UX);
		if (desc & SECTION_PXN)
			a &= ~TEE_MATTR_PX;
		a |= texcb_to_mattr(((desc >> 12) & 0x7) | ((desc >> 2) & 0x3));
		if (!(desc & SECTION_NOTGLOBAL))
			a |= TEE_MATTR_GLOBAL;
		if (!(desc & SECTION_NOTSECURE))
			a |= TEE_MATTR_SECURE;
		break;
	case DESC_TYPE_SMALL_PAGE:
		a = TEE_MATTR_VALID_BLOCK;
		if (desc & SMALL_PAGE_ACCESS_FLAG)
			a |= TEE_MATTR_PRX | TEE_MATTR_URX;
		if (!(desc & SMALL_PAGE_RO))
			a |= TEE_MATTR_PW | TEE_MATTR_UW;
		if (desc & SMALL_PAGE_XN)
			a &= ~(TEE_MATTR_PX | TEE_MATTR_UX);
		a |= texcb_to_mattr(((desc >> 6) & 0x7) | ((desc >> 2) & 0x3));
		if (!(desc & SMALL_PAGE_NOTGLOBAL))
			a |= TEE_MATTR_GLOBAL;
		break;
	case DESC_TYPE_INVALID:
		if (desc & HIDDEN_DESC)
			return TEE_MATTR_HIDDEN_BLOCK;
		if (desc & HIDDEN_DIRTY_DESC)
			return TEE_MATTR_HIDDEN_DIRTY_BLOCK;
		return 0;
	default:
		return 0;
	}
	return a;
}
static uint32_t mattr_to_desc(unsigned level, uint32_t attr)
{
	uint32_t desc;
	uint32_t a = attr;
	unsigned texcb;
	if (a & TEE_MATTR_HIDDEN_BLOCK)
		return INVALID_DESC | HIDDEN_DESC;
	if (a & TEE_MATTR_HIDDEN_DIRTY_BLOCK)
		return INVALID_DESC | HIDDEN_DIRTY_DESC;
	if (level == 1 && (a & TEE_MATTR_TABLE)) {
		desc = SECTION_PT_PT;
		if (!(a & TEE_MATTR_SECURE))
			desc |= SECTION_PT_NOTSECURE;
		return desc;
	}
	if (!(a & TEE_MATTR_VALID_BLOCK))
		return INVALID_DESC;
	if (a & (TEE_MATTR_PX | TEE_MATTR_PW))
		a |= TEE_MATTR_PR;
	if (a & (TEE_MATTR_UX | TEE_MATTR_UW))
		a |= TEE_MATTR_UR;
	if (a & TEE_MATTR_UR)
		a |= TEE_MATTR_PR;
	if (a & TEE_MATTR_UW)
		a |= TEE_MATTR_PW;
	texcb = mattr_to_texcb(a);
	if (level == 1) {	
#ifndef CFG_NO_SMP
		desc = SECTION_SECTION | SECTION_SHARED;
#else
		desc = SECTION_SECTION;
#endif
		if (!(a & (TEE_MATTR_PX | TEE_MATTR_UX)))
			desc |= SECTION_XN;
#ifdef CFG_HWSUPP_MEM_PERM_PXN
		if (!(a & TEE_MATTR_PX))
			desc |= SECTION_PXN;
#endif
		if (a & TEE_MATTR_UR)
			desc |= SECTION_UNPRIV;
		if (!(a & TEE_MATTR_PW))
			desc |= SECTION_RO;
		if (a & (TEE_MATTR_UR | TEE_MATTR_PR))
			desc |= SECTION_ACCESS_FLAG;
		if (!(a & TEE_MATTR_GLOBAL))
			desc |= SECTION_NOTGLOBAL;
		if (!(a & TEE_MATTR_SECURE))
			desc |= SECTION_NOTSECURE;
		desc |= SECTION_TEXCB(texcb);
	} else {
#ifndef CFG_NO_SMP
		desc = SMALL_PAGE_SMALL_PAGE | SMALL_PAGE_SHARED;
#else
		desc = SMALL_PAGE_SMALL_PAGE;
#endif
		if (!(a & (TEE_MATTR_PX | TEE_MATTR_UX)))
			desc |= SMALL_PAGE_XN;
		if (a & TEE_MATTR_UR)
			desc |= SMALL_PAGE_UNPRIV;
		if (!(a & TEE_MATTR_PW))
			desc |= SMALL_PAGE_RO;
		if (a & (TEE_MATTR_UR | TEE_MATTR_PR))
			desc |= SMALL_PAGE_ACCESS_FLAG;
		if (!(a & TEE_MATTR_GLOBAL))
			desc |= SMALL_PAGE_NOTGLOBAL;
		desc |= SMALL_PAGE_TEXCB(texcb);
	}
	return desc;
}
void core_mmu_set_info_table(struct core_mmu_table_info *tbl_info,
		unsigned level, vaddr_t va_base, void *table)
{
	tbl_info->level = level;
	tbl_info->table = table;
	tbl_info->va_base = va_base;
	assert(level <= 2);
	if (level == 1) {
		tbl_info->shift = SECTION_SHIFT;
		tbl_info->num_entries = NUM_L1_ENTRIES;
	} else {
		tbl_info->shift = SMALL_PAGE_SHIFT;
		tbl_info->num_entries = NUM_L2_ENTRIES;
	}
}
void core_mmu_get_user_pgdir(struct core_mmu_table_info *pgd_info)
{
	void *tbl = (void *)core_mmu_get_ul1_ttb_va();
	core_mmu_set_info_table(pgd_info, 1, 0, tbl);
	pgd_info->num_entries = NUM_UL1_ENTRIES;
}
void core_mmu_create_user_map(struct user_ta_ctx *utc,
			      struct core_mmu_user_map *map)
{
	struct core_mmu_table_info dir_info;
	COMPILE_TIME_ASSERT(L2_TBL_SIZE == PGT_SIZE);
	core_mmu_get_user_pgdir(&dir_info);
	memset(dir_info.table, 0, dir_info.num_entries * sizeof(uint32_t));
	core_mmu_populate_user_map(&dir_info, utc);
	map->ttbr0 = core_mmu_get_ul1_ttb_pa() | TEE_MMU_DEFAULT_ATTRS;
	map->ctxid = utc->vm_info->asid;
}
bool core_mmu_find_table(vaddr_t va, unsigned max_level,
		struct core_mmu_table_info *tbl_info)
{
	uint32_t *tbl = (uint32_t *)core_mmu_get_main_ttb_va();
	unsigned n = va >> SECTION_SHIFT;
	if (max_level == 1 || (tbl[n] & 0x3) != 0x1) {
		core_mmu_set_info_table(tbl_info, 1, 0, tbl);
	} else {
		paddr_t ntbl = tbl[n] & ~((1 << 10) - 1);
		void *l2tbl = phys_to_virt(ntbl, MEM_AREA_TEE_RAM_RW_DATA);
		if (!l2tbl)
			return false;
		core_mmu_set_info_table(tbl_info, 2, n << SECTION_SHIFT, l2tbl);
	}
	return true;
}
void core_mmu_set_entry_primitive(void *table, size_t level, size_t idx,
				  paddr_t pa, uint32_t attr)
{
	uint32_t *tbl = table;
	uint32_t desc = mattr_to_desc(level, attr);
	tbl[idx] = desc | pa;
}
static paddr_t desc_to_pa(unsigned level, uint32_t desc)
{
	unsigned shift_mask;
	switch (get_desc_type(level, desc)) {
	case DESC_TYPE_PAGE_TABLE:
		shift_mask = 10;
		break;
	case DESC_TYPE_SECTION:
		shift_mask = 20;
		break;
	case DESC_TYPE_SUPER_SECTION:
		shift_mask = 24; 
		break;
	case DESC_TYPE_LARGE_PAGE:
		shift_mask = 16;
		break;
	case DESC_TYPE_SMALL_PAGE:
		shift_mask = 12;
		break;
	default:
		shift_mask = 4;
	}
	return desc & ~((1 << shift_mask) - 1);
}
bool core_mmu_entry_to_finer_grained(struct core_mmu_table_info *tbl_info,
				     unsigned int idx, bool secure)
{
	uint32_t *new_table;
	uint32_t *entry;
	uint32_t new_table_desc;
	uint32_t attr;
	uint32_t desc;
	paddr_t pa;
	int i;
	if (tbl_info->level != 1)
		return false;
	if (idx >= NUM_L1_ENTRIES)
		return false;
	entry = (uint32_t *)tbl_info->table + idx;
	attr = desc_to_mattr(1, *entry);
	if (*entry && get_desc_type(1, *entry) == DESC_TYPE_PAGE_TABLE) {
		return secure == (bool)(attr & TEE_MATTR_SECURE);
	}
	if (attr && secure != (bool)(attr & TEE_MATTR_SECURE))
		return false;
	new_table = core_mmu_alloc_l2(NUM_L2_ENTRIES * SMALL_PAGE_SIZE);
	if (!new_table)
		return false;
	new_table_desc = SECTION_PT_PT | (uint32_t)new_table;
	if (!secure)
		new_table_desc |= SECTION_PT_NOTSECURE;
	if (*entry) {
		pa = desc_to_pa(1, *entry);
		desc = mattr_to_desc(2, attr);
		for (i = 0; i < NUM_L2_ENTRIES; i++, pa += SMALL_PAGE_SIZE)
			new_table[i] = desc | pa;
	}
	*entry = new_table_desc;
	return true;
}
void core_mmu_get_entry_primitive(const void *table, size_t level,
				  size_t idx, paddr_t *pa, uint32_t *attr)
{
	const uint32_t *tbl = table;
	if (pa)
		*pa = desc_to_pa(level, tbl[idx]);
	if (attr)
		*attr = desc_to_mattr(level, tbl[idx]);
}
void core_mmu_get_user_va_range(vaddr_t *base, size_t *size)
{
	if (base) {
		*base = 1 << SECTION_SHIFT;
	}
	if (size)
		*size = (NUM_UL1_ENTRIES - 1) << SECTION_SHIFT;
}
void core_mmu_get_user_map(struct core_mmu_user_map *map)
{
	map->ttbr0 = read_ttbr0();
	map->ctxid = read_contextidr();
}
void core_mmu_set_user_map(struct core_mmu_user_map *map)
{
	uint32_t exceptions = thread_mask_exceptions(THREAD_EXCP_ALL);
	dsb();  
	write_contextidr(0);
	isb();
	if (map) {
		write_ttbr0(map->ttbr0);
		isb();
		write_contextidr(map->ctxid);
		isb();
	} else {
		write_ttbr0(read_ttbr1());
		isb();
	}
	tlbi_all();
	thread_unmask_exceptions(exceptions);
}
bool core_mmu_user_mapping_is_active(void)
{
	bool ret;
	uint32_t exceptions = thread_mask_exceptions(THREAD_EXCP_ALL);
	ret = read_ttbr0() != read_ttbr1();
	thread_unmask_exceptions(exceptions);
	return ret;
}
static void print_mmap_area(const struct tee_mmap_region *mm __maybe_unused,
				const char *str __maybe_unused)
{
	if (!(mm->attr & TEE_MATTR_VALID_BLOCK))
		debug_print("%s [%08" PRIxVA " %08" PRIxVA "] not mapped",
				str, mm->va, mm->va + mm->size);
	else
		debug_print("%s [%08" PRIxVA " %08" PRIxVA "] %s-%s-%s-%s",
				str, mm->va, mm->va + mm->size,
				mm->attr & (TEE_MATTR_CACHE_CACHED <<
					TEE_MATTR_CACHE_SHIFT) ? "MEM" : "DEV",
				mm->attr & TEE_MATTR_PW ? "RW" : "RO",
				mm->attr & TEE_MATTR_PX ? "X" : "XN",
				mm->attr & TEE_MATTR_SECURE ? "S" : "NS");
}
void map_memarea_sections(const struct tee_mmap_region *mm, uint32_t *ttb)
{
	uint32_t attr = mattr_to_desc(1, mm->attr);
	size_t idx = mm->va >> SECTION_SHIFT;
	paddr_t pa = 0;
	size_t n;
	if (core_mmap_is_end_of_table(mm))
		return;
	print_mmap_area(mm, "section map");
	attr = mattr_to_desc(1, mm->attr);
	if (attr != INVALID_DESC)
		pa = mm->pa;
	n = ROUNDUP(mm->size, SECTION_SIZE) >> SECTION_SHIFT;
	while (n--) {
		assert(!attr || !ttb[idx] || ttb[idx] == (pa | attr));
		ttb[idx] = pa | attr;
		idx++;
		pa += SECTION_SIZE;
	}
}
void core_init_mmu_tables(struct tee_mmap_region *mm)
{
	void *ttb1 = (void *)core_mmu_get_main_ttb_va();
	size_t n;
#ifdef CFG_CORE_UNMAP_CORE_AT_EL0
	COMPILE_TIME_ASSERT(CORE_MMU_L1_TBL_OFFSET ==
			   sizeof(main_mmu_l1_ttb) / 2);
#endif
	memset(ttb1, 0, L1_TBL_SIZE);
#ifdef CFG_CORE_UNMAP_CORE_AT_EL0
	memset(main_mmu_l1_ttb[1], 0, sizeof(main_mmu_l1_ttb[1]));
#endif
	for (n = 0; !core_mmap_is_end_of_table(mm + n); n++)
		if (!core_mmu_is_dynamic_vaspace(mm + n))
			core_mmu_map_region(mm + n);
}
bool core_mmu_place_tee_ram_at_top(paddr_t paddr)
{
	return paddr > 0x80000000;
}
void core_init_mmu_regs(void)
{
	uint32_t prrr;
	uint32_t nmrr;
	paddr_t ttb_pa = core_mmu_get_main_ttb_pa();
	write_sctlr(read_sctlr() | SCTLR_AFE | SCTLR_TRE);
	prrr = ATTR_DEVICE_PRRR | ATTR_NORMAL_CACHED_PRRR;
	nmrr = ATTR_DEVICE_NMRR | ATTR_NORMAL_CACHED_NMRR;
	prrr |= PRRR_NS1 | PRRR_DS1;
	write_prrr(prrr);
	write_nmrr(nmrr);
	write_dacr(DACR_DOMAIN(0, DACR_DOMAIN_PERM_CLIENT) |
		   DACR_DOMAIN(1, DACR_DOMAIN_PERM_CLIENT));
	write_contextidr(0);
	write_ttbcr(TTBCR_N_VALUE);
	write_ttbr0(ttb_pa | TEE_MMU_DEFAULT_ATTRS);
	write_ttbr1(ttb_pa | TEE_MMU_DEFAULT_ATTRS);
}
KEEP_PAGER(core_init_mmu_regs);
enum core_mmu_fault core_mmu_get_fault_type(uint32_t fsr)
{
	assert(!(fsr & FSR_LPAE));
	switch (fsr & FSR_FS_MASK) {
	case 0x1: 
		return CORE_MMU_FAULT_ALIGNMENT;
	case 0x2: 
		return CORE_MMU_FAULT_DEBUG_EVENT;
	case 0x4: 
	case 0x5: 
	case 0x7: 
		return CORE_MMU_FAULT_TRANSLATION;
	case 0xd: 
	case 0xf: 
		if (fsr & FSR_WNR)
			return CORE_MMU_FAULT_WRITE_PERMISSION;
		else
			return CORE_MMU_FAULT_READ_PERMISSION;
	case 0x3: 
	case 0x6: 
		return CORE_MMU_FAULT_ACCESS_BIT;
	case (1 << 10) | 0x6:
		return CORE_MMU_FAULT_ASYNC_EXTERNAL;
	default:
		return CORE_MMU_FAULT_OTHER;
	}
}

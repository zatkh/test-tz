#ifndef SM_SM_H
#define SM_SM_H
#include <compiler.h>
#include <types_ext.h>
struct sm_mode_regs {
	uint32_t usr_sp;
	uint32_t usr_lr;
	uint32_t irq_spsr;
	uint32_t irq_sp;
	uint32_t irq_lr;
	uint32_t fiq_spsr;
	uint32_t fiq_sp;
	uint32_t fiq_lr;
	uint32_t svc_spsr;
	uint32_t svc_sp;
	uint32_t svc_lr;
	uint32_t abt_spsr;
	uint32_t abt_sp;
	uint32_t abt_lr;
	uint32_t und_spsr;
	uint32_t und_sp;
	uint32_t und_lr;
};
struct sm_nsec_ctx {
	struct sm_mode_regs mode_regs;
	uint32_t r8;
	uint32_t r9;
	uint32_t r10;
	uint32_t r11;
	uint32_t r12;
	uint32_t r0;
	uint32_t r1;
	uint32_t r2;
	uint32_t r3;
	uint32_t r4;
	uint32_t r5;
	uint32_t r6;
	uint32_t r7;
	uint32_t mon_lr;
	uint32_t mon_spsr;
};
struct sm_sec_ctx {
	struct sm_mode_regs mode_regs;
	uint32_t r0;
	uint32_t r1;
	uint32_t r2;
	uint32_t r3;
	uint32_t r4;
	uint32_t r5;
	uint32_t r6;
	uint32_t r7;
	uint32_t mon_lr;
	uint32_t mon_spsr;
};
struct sm_ctx {
	uint32_t pad;
	struct sm_sec_ctx sec;
	struct sm_nsec_ctx nsec;
};
#define SM_STACK_TMP_RESERVE_SIZE	sizeof(struct sm_ctx)
struct sm_nsec_ctx *sm_get_nsec_ctx(void);
void *sm_get_sp(void);
void sm_init(vaddr_t stack_pointer);
#ifndef CFG_SM_PLATFORM_HANDLER
static inline bool sm_platform_handler(__unused struct sm_ctx *ctx)
{
	return true;
}
#else
bool sm_platform_handler(struct sm_ctx *ctx);
#endif
void sm_save_modes_regs(struct sm_mode_regs *regs);
void sm_restore_modes_regs(struct sm_mode_regs *regs);
#endif 

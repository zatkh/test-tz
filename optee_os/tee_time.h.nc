#ifndef TEE_TIME_H
#define TEE_TIME_H
#include "tee_api_types.h"
#define TEE_TIME_BOOT_TICKS_HZ  10UL
TEE_Result tee_time_get_sys_time(TEE_Time *time);
uint32_t tee_time_get_sys_time_protection_level(void);
TEE_Result tee_time_get_ta_time(const TEE_UUID *uuid, TEE_Time *time);
TEE_Result tee_time_get_ree_time(TEE_Time *time);
TEE_Result tee_time_set_ta_time(const TEE_UUID *uuid, const TEE_Time *time);
void tee_time_wait(uint32_t milliseconds_delay);
void tee_time_busy_wait(uint32_t milliseconds_delay);
#endif

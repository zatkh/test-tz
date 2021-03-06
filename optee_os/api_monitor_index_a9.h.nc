#ifndef API_MONITOR_INDEX_H
#define API_MONITOR_INDEX_H
#define API_HAL_RET_VALUE_OK 0x00000000
#define API_HAL_RET_VALUE_SERVICE_UNKNWON 0xFFFFFFFF
#define SECURE_SVC_PM       0x70
#define SECURE_SVC_PM_LATE_SUSPEND      (SECURE_SVC_PM + 1)
#define API_MONITOR_BASE_INDEX 0x00000100
#define API_MONITOR_L2CACHE_SETDEBUG_INDEX              (API_MONITOR_BASE_INDEX + 0x00000000)
#define API_MONITOR_L2CACHE_CLEANINVBYPA_INDEX          (API_MONITOR_BASE_INDEX + 0x00000001)
#define API_MONITOR_L2CACHE_SETCONTROL_INDEX            (API_MONITOR_BASE_INDEX + 0x00000002)
#define API_MONITOR_L2CACHE_SETAUXILIARYCONTROL_INDEX   (API_MONITOR_BASE_INDEX + 0x00000009)
#define API_MONITOR_L2CACHE_SETLATENCY_INDEX            (API_MONITOR_BASE_INDEX + 0x00000012)
#define API_MONITOR_L2CACHE_SETPREFETCHCONTROL_INDEX    (API_MONITOR_BASE_INDEX + 0x00000013)
#endif 

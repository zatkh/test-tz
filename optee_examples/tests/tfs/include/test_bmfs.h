#ifndef _TEST_BMFS_H
#define _TEST_BMFS_H

int bmfs_test(void);
int bmfs_create_file_test(void);
int bmfs_delete_file_test(void);
int bmfs_open_file_test(void);
int bmfs_write_file_test(void);
int bmfs_read_file_test(void);
int bmfs_seek_file_test(void);
void bmfs_close_file_test(void);
void bmfs_cleanup(void);
void init_p_file(void);


#endif //_TEST_BMFS_H
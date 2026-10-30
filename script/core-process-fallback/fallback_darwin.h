#ifndef TUNGBOX_PROCESS_FALLBACK_H
#define TUNGBOX_PROCESS_FALLBACK_H
#include <stdint.h>
#include <stddef.h>
struct tb_socket { uint8_t local[16], remote[16]; uint16_t local_port,remote_port; uint32_t pid; int32_t uid; int family,protocol; };
struct tb_socket *tb_process_sockets(size_t *count);
#endif

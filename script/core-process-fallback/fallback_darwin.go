//go:build darwin && cgo

package process

/*
#cgo LDFLAGS: -lproc
#include "fallback_darwin.h"
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"net/netip"
	"sync"
	"time"
	"unsafe"

	"github.com/sagernet/sing-box/adapter"
)

// Keep sysctl as the fast path. On systems that return an empty PCB table to
// GUI-launched helpers, libproc can still identify sockets visible to this user.
var fdSnapshotCache struct {
	sync.Mutex
	created time.Time
	entries map[string][]darwinConnectionEntry
}

func findDarwinProcessByFD(ctx context.Context, network string, source, destination netip.AddrPort) (*adapter.ConnectionOwner, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	fdSnapshotCache.Lock()
	defer fdSnapshotCache.Unlock()
	for attempt := 0; attempt < 2; attempt++ {
		force := attempt > 0
		if force || time.Since(fdSnapshotCache.created) >= darwinSnapshotTTL {
			var count C.size_t
			table := C.tb_process_sockets(&count)
			fdSnapshotCache.entries = make(map[string][]darwinConnectionEntry)
			if table != nil {
				for _, row := range unsafe.Slice(table, int(count)) {
					var local, remote netip.Addr
					if row.family == 4 {
						local = netip.AddrFrom4([4]byte{byte(row.local[0]), byte(row.local[1]), byte(row.local[2]), byte(row.local[3])})
						remote = netip.AddrFrom4([4]byte{byte(row.remote[0]), byte(row.remote[1]), byte(row.remote[2]), byte(row.remote[3])})
					} else {
						var l, r [16]byte
						for i := range l {
							l[i], r[i] = byte(row.local[i]), byte(row.remote[i])
						}
						local, remote = netip.AddrFrom16(l).Unmap(), netip.AddrFrom16(r).Unmap()
					}
					// Both protocols share the snapshot; record matching protocol separately.
					protocol := "tcp"
					if row.protocol == 17 {
						protocol = "udp"
					}
					fdSnapshotCache.entries[protocol] = append(fdSnapshotCache.entries[protocol], darwinConnectionEntry{localAddr: local, remoteAddr: remote, localPort: uint16(row.local_port), remotePort: uint16(row.remote_port), pid: uint32(row.pid), uid: int32(row.uid)})
				}
				C.free(unsafe.Pointer(table))
			}
			fdSnapshotCache.created = time.Now()
		}
		entry, _, err := matchDarwinConnectionEntry(fdSnapshotCache.entries[network], network, normalizeDarwinAddrPort(source), normalizeDarwinAddrPort(destination))
		if err != nil {
			if attempt == 0 {
				continue
			}
			return nil, err
		}
		path, err := getExecPathFromPID(entry.pid)
		if err != nil {
			return nil, ErrNotFound
		}
		return &adapter.ConnectionOwner{UserId: entry.uid, ProcessPath: path}, nil
	}
	return nil, ErrNotFound
}

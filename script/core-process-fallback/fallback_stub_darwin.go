//go:build darwin && !cgo

package process

import (
	"context"
	"github.com/sagernet/sing-box/adapter"
	"net/netip"
)

func findDarwinProcessByFD(context.Context, string, netip.AddrPort, netip.AddrPort) (*adapter.ConnectionOwner, error) {
	return nil, ErrNotFound
}

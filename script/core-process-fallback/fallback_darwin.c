// Supplemental macOS socket lookup. Never elevates privilege or changes sockets.
#include "fallback_darwin.h"
#include <libproc.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>

struct tb_socket *tb_process_sockets(size_t *count) {
 *count=0;
 int size=proc_listpids(PROC_ALL_PIDS,0,NULL,0);
 if(size<=0 || size>1024*1024) return NULL;
 size+=4096;
 int *pids=malloc(size);
 if(!pids) return NULL;
 int n=proc_listpids(PROC_ALL_PIDS,0,pids,size)/sizeof(int);
 struct tb_socket *table=NULL;
 size_t capacity=0;
 for(int i=0;i<n;i++) {
  if(pids[i]<=0) continue;
  int bytes=proc_pidinfo(pids[i],PROC_PIDLISTFDS,0,NULL,0);
  if(bytes<=0 || bytes>16*1024*1024) continue;
  bytes+=1024;
  struct proc_fdinfo *fds=malloc(bytes);
  if(!fds) continue;
  struct proc_bsdinfo bsd;
  int uid=-1;
  if(proc_pidinfo(pids[i],PROC_PIDTBSDINFO,0,&bsd,sizeof(bsd))==sizeof(bsd)) uid=bsd.pbi_uid;
  int nfds=proc_pidinfo(pids[i],PROC_PIDLISTFDS,0,fds,bytes)/sizeof(*fds);
  for(int j=0;j<nfds;j++) {
   if(fds[j].proc_fdtype!=PROX_FDTYPE_SOCKET) continue;
   struct socket_fdinfo si;
   if(proc_pidfdinfo(pids[i],fds[j].proc_fd,PROC_PIDFDSOCKETINFO,&si,sizeof(si))!=sizeof(si)) continue;
   struct in_sockinfo *in;
   if(si.psi.soi_kind==SOCKINFO_TCP) in=&si.psi.soi_proto.pri_tcp.tcpsi_ini;
   else if(si.psi.soi_kind==SOCKINFO_IN && si.psi.soi_protocol==IPPROTO_UDP) in=&si.psi.soi_proto.pri_in;
   else continue;
   if(si.psi.soi_family!=AF_INET && si.psi.soi_family!=AF_INET6) continue;
   if(*count==capacity) {
    size_t next=capacity?capacity*2:256;
    if(next>131072) { free(fds);free(pids);free(table);*count=0;return NULL; }
    void *grown=realloc(table,next*sizeof(*table));
    if(!grown) { free(fds);free(pids);free(table);*count=0;return NULL; }
    table=grown;capacity=next;
   }
   struct tb_socket *row=&table[(*count)++];
   memset(row,0,sizeof(*row));
   row->pid=pids[i];row->uid=uid;
   row->local_port=ntohs((uint16_t)in->insi_lport);row->remote_port=ntohs((uint16_t)in->insi_fport);
   row->protocol=si.psi.soi_protocol;
   if(in->insi_vflag&INI_IPV4) {
    row->family=4;
    memcpy(row->local,&in->insi_laddr.ina_46.i46a_addr4,4);
    memcpy(row->remote,&in->insi_faddr.ina_46.i46a_addr4,4);
   } else {
    row->family=6;
    memcpy(row->local,&in->insi_laddr.ina_6,16);
    memcpy(row->remote,&in->insi_faddr.ina_6,16);
   }
  }
  free(fds);
 }
 free(pids);
 return table;
}

#-*-mode:hcl;indent-tabs-mode:nil;tab-width:2;coding:utf-8-*-
# vi: ft=hcl tabstop=2 shiftwidth=2 softtabstop=2 expandtab:
cluster {
  node_id = "demo-node"
  advertise = "0.0.0.0:7654"
  backend = "consul://127.0.0.1:8500"
  ttl = "3m"
  retry = "30s"
}

storage "file" {
  path = "/home/terraform/vaultdata"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_cert_file = "/etc/letsencrypt/live/${domain}/fullchain.pem"
  tls_key_file = "/etc/letsencrypt/live/${domain}/privkey.pem"
}

seal "gcpckms" {
  project     = "${project}"
  region      = "${region}"
  key_ring    = "${key_ring}"
  crypto_key  = "${crypto_key}"
}

api_addr = "https://${domain}:8200"
ui = true

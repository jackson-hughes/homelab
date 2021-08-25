resource "aws_route53_zone" "jhcloud" {
  name = "jhcloud.io"
}

resource "aws_route53_zone" "lan_jhcloud" {
  name = "lan.jhcloud.io"
}

resource "aws_route53_record" "lan_jhcloud_ns" {
  zone_id = aws_route53_zone.jhcloud.zone_id
  name    = "lan.jhcloud.io"
  type    = "NS"
  ttl     = 300
  records = aws_route53_zone.lan_jhcloud.name_servers
}

resource "aws_route53_zone" "svc_lan_jhcloud" {
  name = "svc.lan.jhcloud.io"
}

resource "aws_route53_record" "svc_lan_jhcloud_ns" {
  zone_id = aws_route53_zone.lan_jhcloud.zone_id
  name    = "svc.lan.jhcloud.io"
  type    = "NS"
  ttl     = 300
  records = aws_route53_zone.svc_lan_jhcloud.name_servers
}

resource "aws_route53_zone" "zentech" {
  name = "zentech.xyz"
}

resource "aws_route53_record" "mx" {
  zone_id = aws_route53_zone.jhcloud.zone_id
  name    = "jhcloud.io"
  type    = "MX"
  ttl     = 3600
  records = [
    "1 ASPMX.L.GOOGLE.COM.",
    "5 ALT1.ASPMX.L.GOOGLE.COM.",
    "5 ALT2.ASPMX.L.GOOGLE.COM.",
    "10 ALT3.ASPMX.L.GOOGLE.COM.",
    "10 ALT4.ASPMX.L.GOOGLE.COM.",
  ]
}

resource "aws_route53_record" "docs_cname" {
  zone_id = aws_route53_zone.jhcloud.zone_id
  name    = "docs.jhcloud.io"
  type    = "CNAME"
  ttl     = 300
  records = ["jhughes01.github.io."]
}


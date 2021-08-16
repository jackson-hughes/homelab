resource "aws_route53_zone" "jhcloud" {
  name = "jhcloud.io"
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


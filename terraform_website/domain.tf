resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "www.cea27.com"
  type    = "A"

  alias {
    name                   = aws_s3_bucket.website.bucket_domain_name
    zone_id                = aws_s3_bucket.website.hosted_zone_id
    evaluate_target_health = false
  }
}
resource "aws_route53_record" "alias2" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "cea27.com"
  type    = "A"

  alias {
    name                   = aws_s3_bucket.website.bucket_domain_name
    zone_id                = aws_s3_bucket.website.hosted_zone_id
    evaluate_target_health = false
  }
}
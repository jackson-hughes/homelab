resource "aws_iam_user" "certbot" {
    name = "dnsserviceuser"
}

resource "aws_iam_user_policy_attachment" "dns" {
  user = aws_iam_user.certbot.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
}

resource "aws_iam_user" "acme" {
  name = "acme"
}

resource "aws_iam_user_policy_attachment" "dns" {
  user       = aws_iam_user.acme.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
}

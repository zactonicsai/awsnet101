variable "zone_id" {
  description = "EXISTING Route 53 hosted zone ID. Look up a zone you own with the aws_route53_zone data source; do not create zones from automation."
  type        = string
}

variable "records" {
  description = <<-EOT
    Records to create, keyed by a stable name.

    ALIAS record (points at an AWS resource -- free queries, works at the zone root):
      records = {
        app = {
          name           = "app.example.com"
          type           = "A"
          alias_name     = module.alb.alb_dns_name
          alias_zone_id  = module.alb.alb_zone_id
        }
      }

    Standard record:
      records = {
        txt = { name = "example.com", type = "TXT", ttl = 300, values = ["v=spf1 -all"] }
      }
  EOT
  type = map(object({
    name = string
    type = string

    # Standard records
    ttl    = optional(number, 300)
    values = optional(list(string))

    # Alias records
    alias_name             = optional(string)
    alias_zone_id          = optional(string)
    evaluate_target_health = optional(bool, true)

    allow_overwrite = optional(bool, false)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, r in var.records :
      (try(length(r.values), 0) > 0) != (try(r.alias_name, null) != null)
    ])
    error_message = "Each record must be EITHER a standard record (values) OR an alias record (alias_name + alias_zone_id), never both and never neither."
  }

  validation {
    condition = alltrue([
      for k, r in var.records :
      try(r.alias_name, null) == null || try(r.alias_zone_id, null) != null
    ])
    error_message = "An alias record requires alias_zone_id. For an ALB pass module.alb.alb_zone_id -- the LOAD BALANCER's zone, not your domain's."
  }
}

# Edge Functions

Edge Functions are added only with the vertical slice that uses them. The first
planned function is `product-metadata`, which will validate the authenticated
caller, reject private/internal network targets, limit response size and
redirects, and return editable best-effort metadata.

No service-role key belongs in this directory or in a client-visible response.

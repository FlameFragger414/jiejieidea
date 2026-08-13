"""Integration test proving final-unit reservation serialization.

Run against the local Supabase database after `supabase db reset`. The default
connection string is intentionally local-only and may be overridden with
SUPABASE_TEST_DATABASE_URL in CI.
"""

from __future__ import annotations

import os
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor

import psycopg


DATABASE_URL = os.environ.get(
    "SUPABASE_TEST_DATABASE_URL",
    "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
)


def authenticate(cursor: psycopg.Cursor, user_id: uuid.UUID) -> None:
    cursor.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(user_id),))
    cursor.execute(
        "select set_config('request.jwt.claims', %s, true)",
        (f'{{"sub":"{user_id}","role":"authenticated"}}',),
    )
    cursor.execute("set local role authenticated")


def reserve(
    barrier: threading.Barrier,
    user_id: uuid.UUID,
    item_id: uuid.UUID,
) -> str:
    try:
        with psycopg.connect(DATABASE_URL) as connection:
            with connection.cursor() as cursor:
                authenticate(cursor, user_id)
                barrier.wait(timeout=10)
                cursor.execute(
                    """
                    select reservation_id
                    from public.reserve_wishlist_item(%s, 1, null, %s, null)
                    """,
                    (item_id, uuid.uuid4()),
                )
                cursor.fetchone()
        return "reserved"
    except psycopg.Error as error:
        if "insufficient_quantity" in str(error):
            return "insufficient_quantity"
        raise


def main() -> None:
    owner_id, giver_one_id, giver_two_id = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    wishlist_id, item_id = uuid.uuid4(), uuid.uuid4()

    with psycopg.connect(DATABASE_URL) as connection:
        with connection.cursor() as cursor:
            for user_id, email in (
                (owner_id, "concurrency-owner@test.invalid"),
                (giver_one_id, "concurrency-one@test.invalid"),
                (giver_two_id, "concurrency-two@test.invalid"),
            ):
                cursor.execute(
                    """
                    insert into auth.users (
                      instance_id, id, aud, role, email, encrypted_password,
                      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                      created_at, updated_at
                    ) values (
                      '00000000-0000-0000-0000-000000000000', %s,
                      'authenticated', 'authenticated', %s, '', now(), '{}',
                      jsonb_build_object('display_name', 'Concurrency test'),
                      now(), now()
                    )
                    """,
                    (user_id, email),
                )

            cursor.execute(
                """
                insert into public.wishlists (id, owner_id, name, visibility)
                values (%s, %s, 'Concurrency test', 'public')
                """,
                (wishlist_id, owner_id),
            )
            cursor.execute(
                """
                insert into public.wishlist_items (
                  id, wishlist_id, product_name, desired_quantity
                ) values (%s, %s, 'Only one left', 1)
                """,
                (item_id, wishlist_id),
            )

    barrier = threading.Barrier(2)
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [
            executor.submit(reserve, barrier, giver_one_id, item_id),
            executor.submit(reserve, barrier, giver_two_id, item_id),
        ]
        outcomes = sorted(future.result(timeout=20) for future in futures)

    expected = ["insufficient_quantity", "reserved"]
    if outcomes != expected:
        raise AssertionError(f"Expected {expected}, got {outcomes}")

    with psycopg.connect(DATABASE_URL) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "select count(*), coalesce(sum(quantity), 0) from public.gift_reservations where wishlist_item_id = %s and status in ('reserved', 'purchased')",
                (item_id,),
            )
            count, quantity = cursor.fetchone()
            if (count, quantity) != (1, 1):
                raise AssertionError(f"Expected one active unit, got count={count}, quantity={quantity}")
            cursor.execute("delete from auth.users where id = any(%s)", ([owner_id, giver_one_id, giver_two_id],))

    print("Concurrent final-unit reservation test passed.")


if __name__ == "__main__":
    main()

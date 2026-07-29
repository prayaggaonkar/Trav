-- Allow users to delete their own notifications (swipe-to-delete in inbox).
drop policy if exists "Users can delete their notifications" on public.notifications;
create policy "Users can delete their notifications"
  on public.notifications for delete
  using (auth.uid() = user_id);

grant delete on public.notifications to authenticated;

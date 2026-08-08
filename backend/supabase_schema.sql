-- ConfidenceLD - Schéma de la base de données
-- À exécuter une seule fois dans le SQL Editor de Supabase

create table if not exists users (
  id serial primary key,
  username text unique not null,
  display_name text not null,
  salt text not null,
  hash text not null,
  created_at timestamptz default now()
);

create table if not exists conversations (
  id serial primary key,
  user1 integer not null,
  user2 integer not null,
  last_message_at timestamptz,
  unique (user1, user2)
);

create table if not exists messages (
  id serial primary key,
  conversation_id integer not null references conversations(id),
  sender_id integer not null references users(id),
  type text not null default 'text',
  content text,
  media_id integer,
  view_once boolean not null default false,
  status text not null default 'sent',
  created_at timestamptz default now()
);

create table if not exists media (
  id serial primary key,
  filename text not null,
  mimetype text not null,
  owner_id integer not null references users(id),
  created_at timestamptz default now()
);
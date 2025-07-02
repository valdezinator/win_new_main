# Cresca - Music Streaming Desktop Application

A cross-platform desktop application for Windows, macOS, Linux, and web.

## Overview

The application follows a modern desktop-style navigation similar to popular music streaming platforms like Spotify, Apple Music, and YouTube Music. It features a static left sidebar for navigation and a persistent music player at the bottom.

Current layout:
Currently a layout has been set up. But it should be changed.

There is an "images" folder in the root level of my project. Files include Home Page.png, Search Page.png, Search Results.png, Opened Album.png and several others. Go through the images to get a better idea of the layout, colors to be used for the UI.

## Layout Components

### Home Page

#### 1. Quick Play Section
- Displays 8 random songs from Supabase
- Data source: `songs_2` table
- Fields: id, title, artist, image_url, audio_url, play_count

#### 2. Just the Hits
- Displays albums from `albums` table
- Shows albums with category "album, hits"
- Fields: id, title, artist, image_url, release_year, popularity_score, category

#### 3. New Releases
- Located below Just the Hits
- Shows albums with category "album, new releases"
- Uses same data structure as Just the Hits

#### 4. Recommended Artists
- Displays artists from `artists` table
- Fields: id, name, image_url

#### 5. Dynamic Playlists
- TODO: Future implementation

### Search Page

#### Features
1. Recently Played Tracks
   - Hidden for new users
   - Appears after search history builds up
   - Shows tracks played from search results

2. Recently Played Albums
   - Hidden for new users
   - Shows albums played from search results
   - Requires at least one song played from the album

3. Discover Section
   - Located below recent sections
   - Similar to standard music platform discovery sections

### Album View

#### Layout
- Detailed album information display
- Song list from `songs_2` table
- Uses album_id as foreign key to link with albums table

## Database Structure

### Tables

1. songs_2
   - id
   - title
   - artist
   - image_url
   - audio_url
   - play_count
   - album_id (foreign key)

2. albums
   - id
   - title
   - artist
   - image_url
   - release_year
   - popularity_score
   - category

3. artists
   - id
   - name
   - image_url

## Navigation

- Persistent left sidebar
- Static bottom music player
- Content changes in main area only
- Seamless navigation between views

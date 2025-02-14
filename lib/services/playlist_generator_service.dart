import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'package:flutter/material.dart';

class PlaylistPromptAnalysis {
  final List<String> moods;
  final List<String> genres;
  final List<String> activities;
  final String? tempo;
  final List<String> artists;
  final String? timeOfDay;

  PlaylistPromptAnalysis({
    this.moods = const [],
    this.genres = const [],
    this.activities = const [],
    this.tempo,
    this.artists = const [],
    this.timeOfDay,
  });
}

class PlaylistGeneratorService {
  final SupabaseClient supabaseClient;
  final Random _random = Random();

  // Mood mappings
  static final Map<String, List<String>> moodSynonyms = {
    'chill': ['relaxed', 'calm', 'peaceful', 'mellow', 'laid-back'],
    'energetic': ['upbeat', 'lively', 'dynamic', 'pumped', 'high-energy'],
    'happy': ['joyful', 'cheerful', 'uplifting', 'positive', 'feel-good'],
    'sad': ['melancholic', 'emotional', 'down', 'blue', 'gloomy'],
    'romantic': ['love', 'sweet', 'passionate', 'dreamy'],
    'dark': ['moody', 'intense', 'heavy', 'deep'],
    'party': ['fun', 'dance', 'celebration', 'groove'],
  };

  // Genre mappings for broader categories
  static final Map<String, List<String>> genreCategories = {
    'pop': ['pop', 'dance pop', 'synth pop', 'indie pop', 'k-pop', 'j-pop'],
    'rock': ['rock', 'alternative rock', 'indie rock', 'hard rock', 'metal', 'punk'],
    'electronic': ['electronic', 'edm', 'house', 'techno', 'dance', 'dubstep', 'trance'],
    'hip-hop': ['hip hop', 'rap', 'trap', 'r&b', 'grime'],
    'classical': ['classical', 'orchestra', 'piano', 'instrumental', 'symphony'],
    'jazz': ['jazz', 'blues', 'swing', 'bebop', 'fusion'],
    'country': ['country', 'folk', 'americana', 'bluegrass'],
    'latin': ['latin', 'reggaeton', 'salsa', 'bachata', 'merengue'],
  };

  PlaylistGeneratorService({required this.supabaseClient});

  PlaylistPromptAnalysis analyzePrompt(String prompt) {
    final promptLower = prompt.toLowerCase();
    final words = promptLower.split(RegExp(r'\s+'));
    
    List<String> moods = [];
    List<String> genres = [];
    List<String> activities = [];
    String? tempo;
    List<String> artists = [];
    String? timeOfDay;

    // Process moods with better context awareness
    for (var mood in moodSynonyms.keys) {
      if (promptLower.contains(mood)) {
        moods.add(mood);
      } else {
        for (var synonym in moodSynonyms[mood]!) {
          if (promptLower.contains(synonym)) {
            moods.add(mood);
            break;
          }
        }
      }
    }

    // Process genres with fuzzy matching
    for (var genre in genreCategories.keys) {
      if (promptLower.contains(genre)) {
        genres.add(genre);
      } else {
        for (var subgenre in genreCategories[genre]!) {
          if (words.contains(subgenre) || promptLower.contains(subgenre)) {
            genres.add(genre);
            break;
          }
        }
      }
    }

    // Enhanced tempo analysis
    if (promptLower.contains('fast') || promptLower.contains('upbeat') || 
        promptLower.contains('energetic') || promptLower.contains('quick')) {
      tempo = 'fast';
    } else if (promptLower.contains('slow') || promptLower.contains('mellow') || 
               promptLower.contains('calm') || promptLower.contains('relaxing')) {
      tempo = 'slow';
    } else if (promptLower.contains('moderate') || promptLower.contains('medium')) {
      tempo = 'medium';
    }

    // Activity detection with context
    final commonActivities = {
      'workout': ['exercise', 'gym', 'training', 'fitness'],
      'study': ['studying', 'focus', 'concentration', 'work'],
      'sleep': ['sleeping', 'relaxation', 'bedtime', 'rest'],
      'party': ['dancing', 'celebration', 'club', 'festive'],
      'drive': ['driving', 'road trip', 'travel', 'journey'],
      'meditation': ['yoga', 'mindfulness', 'zen', 'spiritual'],
    };

    for (var activity in commonActivities.keys) {
      if (promptLower.contains(activity) || 
          commonActivities[activity]!.any((synonym) => promptLower.contains(synonym))) {
        activities.add(activity);
      }
    }

    // Artist detection
    final artistIndicators = ['like', 'similar to', 'by', 'such as'];
    for (var indicator in artistIndicators) {
      var index = promptLower.indexOf(indicator);
      if (index != -1) {
        var remaining = promptLower.substring(index + indicator.length).trim();
        var potentialArtist = remaining.split(RegExp(r'[,\s]'))[0].trim();
        if (potentialArtist.isNotEmpty) {
          artists.add(potentialArtist);
        }
      }
    }

    // Time context detection with fuzzy matching
    final timeContexts = {
      'morning': ['sunrise', 'dawn', 'breakfast', 'early'],
      'afternoon': ['lunch', 'midday', 'noon'],
      'evening': ['sunset', 'dusk', 'dinner'],
      'night': ['midnight', 'late', 'bedtime', 'dark'],
    };

    for (var entry in timeContexts.entries) {
      if (promptLower.contains(entry.key) || 
          entry.value.any((synonym) => promptLower.contains(synonym))) {
        timeOfDay = entry.key;
        break;
      }
    }

    return PlaylistPromptAnalysis(
      moods: moods,
      genres: genres,
      activities: activities,
      tempo: tempo,
      artists: artists,
      timeOfDay: timeOfDay,
    );
  }

  Future<List<Map<String, dynamic>>> generatePlaylist(String prompt) async {
    final analysis = analyzePrompt(prompt);
    try {
      List<Map<String, dynamic>> allSongs = [];
      
      // First try to fetch songs by artist if specified
      if (analysis.artists.isNotEmpty) {
        final artistSongs = await _fetchSongsByArtists(analysis.artists);
        allSongs.addAll(artistSongs);
      }

      // Then fetch songs by genre
      var query = supabaseClient
          .from('songs')
          .select();

      if (analysis.genres.isNotEmpty) {
        final genrePatterns = analysis.genres.expand(
          (genre) => [genre, ...?genreCategories[genre]]
        ).toList();
        
        query = query.or(genrePatterns.map((g) => 'genre.ilike.%$g%').join(','));
      }

      final data = await query;
      List<Map<String, dynamic>> genreSongs = List<Map<String, dynamic>>.from(data);
      allSongs.addAll(genreSongs);

      // Remove duplicates
      final uniqueSongs = {
        for (var song in allSongs)
          song['id'].toString(): song
      }.values.toList();

      // Score and filter songs with null safety
      final scoredSongs = uniqueSongs.map((song) {
        double score = calculateSongScore(song, analysis);
        return {'song': song, 'score': score};
      }).where((scored) {
        final score = scored['score'] as double?;
        return score != null && score > 0.3;
      }).toList();

      // Sort by score with null safety
      scoredSongs.sort((a, b) {
        final scoreA = a['score'] as double? ?? 0.0;
        final scoreB = b['score'] as double? ?? 0.0;
        return scoreB.compareTo(scoreA);
      });
      
      // Take top 30 songs
      var selectedSongs = scoredSongs.take(30).map((scored) => scored['song'] as Map<String, dynamic>).toList();

      // If we need more songs, fetch related ones
      if (selectedSongs.length < 30) {
        final additionalSongs = await fetchRelatedSongs(analysis, selectedSongs.length);
        selectedSongs.addAll(additionalSongs);
      }

      // Ensure we don't exceed 30 songs and shuffle
      selectedSongs = selectedSongs.take(30).toList()..shuffle(_random);

      return selectedSongs;
    } catch (e) {
      print('Error generating playlist: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSongsByArtists(List<String> artists) async {
    try {
      final data = await supabaseClient
          .from('songs')
          .select()
          .or(artists.map((artist) => 'artist.ilike.%$artist%').join(','))
          .limit(15);
      
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      print('Error fetching songs by artists: $e');
      return [];
    }
  }

  double calculateSongScore(Map<String, dynamic> song, PlaylistPromptAnalysis analysis) {
    double score = 0.0;
    final songGenre = (song['genre'] as String?)?.toLowerCase() ?? '';
    final songTitle = (song['title'] as String?)?.toLowerCase() ?? '';
    final artist = (song['artist'] as String?)?.toLowerCase() ?? '';

    // Genre matching (up to 0.4)
    if (analysis.genres.isNotEmpty) {
      for (var genre in analysis.genres) {
        if (songGenre.contains(genre) || 
            genreCategories[genre]?.any((subgenre) => songGenre.contains(subgenre)) == true) {
          score += 0.4;
          break;
        }
      }
    }

    // Mood matching (up to 0.3)
    if (analysis.moods.isNotEmpty) {
      for (var mood in analysis.moods) {
        if (songTitle.contains(mood) || 
            moodSynonyms[mood]?.any((synonym) => songTitle.contains(synonym)) == true) {
          score += 0.3;
          break;
        }
      }
    }

    // Artist matching (up to 0.4)
    if (analysis.artists.isNotEmpty) {
      if (analysis.artists.any((requestedArtist) => 
          artist.contains(requestedArtist.toLowerCase()))) {
        score += 0.4;
      }
    }

    // Activity context bonus (up to 0.2)
    if (analysis.activities.isNotEmpty) {
      for (var activity in analysis.activities) {
        if (songTitle.contains(activity)) {
          score += 0.2;
          break;
        }
      }
    }

    // Tempo matching (up to 0.2)
    if (analysis.tempo != null) {
      final duration = song['duration'] as int?;
      if (duration != null) {
        if (analysis.tempo == 'fast' && duration < 240) {
          score += 0.2;
        } else if (analysis.tempo == 'slow' && duration > 240) {
          score += 0.2;
        }
      }
    }

    return score;
  }

  Future<List<Map<String, dynamic>>> fetchRelatedSongs(
    PlaylistPromptAnalysis analysis,
    int existingCount) async {
    final neededSongs = 30 - existingCount;
    if (neededSongs <= 0) return [];

    // Get related genres and expanded mood context
    final relatedGenres = <String>[];
    final relatedMoods = <String>[];

    for (var genre in analysis.genres) {
      if (genreCategories.containsKey(genre)) {
        relatedGenres.addAll(genreCategories[genre]!);
      }
    }

    for (var mood in analysis.moods) {
      if (moodSynonyms.containsKey(mood)) {
        relatedMoods.addAll(moodSynonyms[mood]!);
      }
    }

    try {
      var query = supabaseClient
          .from('songs')
          .select();

      if (relatedGenres.isNotEmpty) {
        // Fix: Using contains instead of in_ for genre matching
        query = query.or(relatedGenres.map((g) => 'genre.ilike.%$g%').join(','));
      }

      final data = await query.limit(neededSongs);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      print('Error fetching related songs: $e');
      return [];
    }
  }

  String generatePlaylistDescription(PlaylistPromptAnalysis analysis) {
    final description = StringBuffer();
    
    if (analysis.moods.isNotEmpty) {
      description.write('A ${analysis.moods.join(' and ')} playlist ');
    }
    
    if (analysis.genres.isNotEmpty) {
      description.write('featuring ${analysis.genres.join(' and ')} music ');
    }
    
    if (analysis.artists.isNotEmpty) {
      description.write('inspired by ${analysis.artists.join(', ')} ');
    }
    
    if (analysis.activities.isNotEmpty) {
      description.write('perfect for ${analysis.activities.join(' and ')} ');
    }
    
    if (analysis.timeOfDay != null) {
      description.write('during ${analysis.timeOfDay} ');
    }
    
    return description.toString().trim();
  }
}

// New Widget: PlaylistGeneratorScreen - UI for AI Playlist Assistant
class PlaylistGeneratorScreen extends StatefulWidget {
  final SupabaseClient supabaseClient;

  const PlaylistGeneratorScreen({Key? key, required this.supabaseClient}) : super(key: key);

  @override
  _PlaylistGeneratorScreenState createState() => _PlaylistGeneratorScreenState();
}

class _PlaylistGeneratorScreenState extends State<PlaylistGeneratorScreen> {
  final TextEditingController _playlistNameController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [
    // Dummy conversation messages
    {'sender': 'AI', 'text': 'Hello, how can I assist you?'},
    {'sender': 'User', 'text': 'I need a chill playlist.'},
  ];
  final List<Map<String, String>> _tracks = [
    // Dummy track preview data
    {'title': 'Song 1', 'artist': 'Artist A', 'image': ''},
    {'title': 'Song 2', 'artist': 'Artist B', 'image': ''},
    {'title': 'Song 3', 'artist': 'Artist C', 'image': ''},
  ];
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.music_note),
            const SizedBox(width: 8),
            const Text('AI Playlist Assistant'),
            const Spacer(),
            TextButton(onPressed: () {}, child: const Text('Home')),
            TextButton(onPressed: () {}, child: const Text('Library')),
            TextButton(onPressed: () {}, child: const Text('Settings')),
            IconButton(onPressed: () {}, icon: const Icon(Icons.brightness_6)),
          ],
        ),
        backgroundColor: Colors.black87,
        elevation: 2,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isWide = constraints.maxWidth > 800;
          return Column(
            children: [
              Expanded(
                child: isWide
                    ? Row(
                        children: [
                          Expanded(child: _buildConversationPanel()),
                          const VerticalDivider(width: 1, color: Colors.grey),
                          Expanded(child: _buildConfigurationPanel()),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildConversationPanel(),
                            const Divider(color: Colors.grey),
                            _buildConfigurationPanel(),
                          ],
                        ),
                      ),
              ),
              Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(8),
                alignment: Alignment.center,
                child: const Text('© 2023 AI Playlist Assistant',
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConversationPanel() {
    return Container(
      color: Colors.grey[900],
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              reverse: true,
              itemBuilder: (context, index) {
                final message = _messages[_messages.length - 1 - index];
                final bool isUser = message['sender'] == 'User';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blueAccent : Colors.grey[700],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      message['text'],
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (value) {
                      setState(() {
                        _messages.add({'sender': 'User', 'text': value});
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationPanel() {
    return Container(
      color: Colors.grey[850],
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Playlist Configuration',
                style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
              controller: _playlistNameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Playlist Name',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                // Trigger cover image uploader (with drag and drop if on web)
              },
              child: const Text('Upload Cover Image'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _promptController,
              style: const TextStyle(color: Colors.white),
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Describe the vibe you’re looking for…',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _isGenerating
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _generatePlaylist,
                    child: const Text('Create Playlist'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
            const SizedBox(height: 24),
            const Text('Track Preview',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            _buildTrackPreview(),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Finalize playlist creation
              },
              child: const Text('Finalize Playlist'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackPreview() {
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _tracks.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.7,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final track = _tracks[index];
            return Container(
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Container(
                    height: 60,
                    width: 60,
                    color: Colors.grey,
                    child: track['image'] == ''
                        ? const Icon(Icons.music_note, color: Colors.white)
                        : Image.network(track['image']!),
                  ),
                  const SizedBox(height: 8),
                  Text(track['title'] ?? '',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center),
                  Text(track['artist'] ?? '',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 10),
                      textAlign: TextAlign.center),
                  IconButton(
                    icon: const Icon(Icons.play_arrow,
                        size: 20, color: Colors.white),
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            );
          },
        ),
        if (_tracks.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('and ${_tracks.length - 3} more tracks...',
                style: const TextStyle(color: Colors.white70)),
          ),
      ],
    );
  }

  Future<void> _generatePlaylist() async {
    setState(() {
      _isGenerating = true;
    });
    // Use PlaylistGeneratorService to generate playlist based on the prompt.
    final service = PlaylistGeneratorService(supabaseClient: widget.supabaseClient);
    try {
      final prompt = _promptController.text;
      final songs = await service.generatePlaylist(prompt);
      // Update track preview (displaying up to 3 tracks)
      setState(() {
        _tracks.clear();
        for (var song in songs.take(3)) {
          _tracks.add({
            'title': song['title'] ?? '',
            'artist': song['artist'] ?? '',
            'image': song['image_url'] ?? '',
          });
        }
      });
    } catch (e) {
      // Add error feedback via snackbar or inline message
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }
}
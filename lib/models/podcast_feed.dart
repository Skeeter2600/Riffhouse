class PodcastFeed {
  final String id;
  final String title;
  final String publisher;
  final String rssUrl;
  final String imageUrl;
  final String description;
  final String category;

  const PodcastFeed({
    required this.id,
    required this.title,
    required this.publisher,
    required this.rssUrl,
    required this.imageUrl,
    required this.description,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'publisher': publisher,
        'rssUrl': rssUrl,
        'imageUrl': imageUrl,
        'description': description,
        'category': category,
      };

  factory PodcastFeed.fromJson(Map<String, dynamic> json) => PodcastFeed(
        id: json['id'] as String,
        title: json['title'] as String,
        publisher: json['publisher'] as String,
        rssUrl: json['rssUrl'] as String,
        imageUrl: json['imageUrl'] as String,
        description: json['description'] as String,
        category: json['category'] as String? ?? 'General',
      );
}

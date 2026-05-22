part of '../dashboard_tab.dart';



class _ImageThumb extends StatelessWidget {
  final String url;

  const _ImageThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _FullscreenImageViewer(imageUrl: url),
          ),
        );
      },
      child: Hero(
        tag: url,
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _kBorderH,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: _kSurface,
              child: const Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kCopper,
                  ),
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              color: _kSurface,
              child: const Icon(
                Icons.broken_image_outlined,
                color: _kSub,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

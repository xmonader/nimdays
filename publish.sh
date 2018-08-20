softcover build:html
rm -rf docs
cp -R html docs
rm -rf docs/images
cp -R images docs/
mv docs/nimdays.html docs/index.html
